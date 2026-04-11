"""
POST /segment-wall
Connected-region flood fill on SLIC superpixels.
Expands only through *adjacent* superpixels — cannot jump to ceiling/floor.
"""
import base64
import io
from collections import deque

import numpy as np
from flask import Blueprint, jsonify, request
from PIL import Image, ImageFilter, ImageOps

segment_wall_bp = Blueprint("segment_wall", __name__)

WORK_SIZE = 512


def _resize_work(pil: Image.Image):
    w, h = pil.size
    scale = WORK_SIZE / max(w, h)
    nw, nh = int(w * scale), int(h * scale)
    return pil.resize((nw, nh), Image.BILINEAR)


def _build_adjacency(segments: np.ndarray):
    """Return dict: label → set of adjacent labels (4-connectivity)."""
    adj = {}
    n = int(segments.max()) + 1
    for i in range(n):
        adj[i] = set()

    h, w = segments.shape
    for r in range(h):
        for c in range(w):
            lbl = int(segments[r, c])
            for dr, dc in ((0, 1), (1, 0)):
                nr, nc = r + dr, c + dc
                if 0 <= nr < h and 0 <= nc < w:
                    nb = int(segments[nr, nc])
                    if nb != lbl:
                        adj[lbl].add(nb)
                        adj[nb].add(lbl)
    return adj


def _lab_mean(px: np.ndarray):
    from skimage.color import rgb2lab
    return rgb2lab(px.mean(axis=0).reshape(1, 1, 3)).reshape(3)


def _segment_flood(pil: Image.Image, seed_x: float, seed_y: float) -> Image.Image:
    """BFS flood fill from tapped superpixel through adjacent similar-color regions."""
    from skimage.segmentation import slic
    from skimage.util import img_as_float

    small = _resize_work(pil)
    arr = img_as_float(np.array(small))
    segments = slic(arr, n_segments=300, compactness=12, sigma=1,
                    start_label=0, channel_axis=2)

    h, w = segments.shape
    sy = int(seed_y * h)
    sx = int(seed_x * w)
    sy = max(0, min(sy, h - 1))
    sx = max(0, min(sx, w - 1))
    seed_lbl = int(segments[sy, sx])

    # Per-label LAB mean
    n_labels = int(segments.max()) + 1
    lab_means = {}
    for lbl in range(n_labels):
        px = arr[segments == lbl]
        if len(px):
            lab_means[lbl] = _lab_mean(px)

    seed_lab = lab_means[seed_lbl]

    # Build adjacency once
    adj = _build_adjacency(segments)

    # BFS: only cross into adjacent superpixel if its color is close enough
    THRESHOLD = 14   # perceptual LAB delta-E — tight enough to stop at edges

    visited = {seed_lbl}
    queue = deque([seed_lbl])
    selected = {seed_lbl}

    while queue:
        lbl = queue.popleft()
        for nb in adj[lbl]:
            if nb in visited:
                continue
            visited.add(nb)
            nb_lab = lab_means.get(nb)
            if nb_lab is None:
                continue
            dist = float(np.linalg.norm(nb_lab - seed_lab))
            if dist < THRESHOLD:
                selected.add(nb)
                queue.append(nb)

    out = np.zeros((h, w), dtype=np.uint8)
    for lbl in selected:
        out[segments == lbl] = 255

    return Image.fromarray(out, mode="L").resize(pil.size, Image.NEAREST)


def _segment_auto(pil: Image.Image, surface: str) -> Image.Image:
    """Fallback when no tap seed — spatial heuristic."""
    from skimage.segmentation import slic
    from skimage.util import img_as_float
    from skimage.color import rgb2lab

    small = _resize_work(pil)
    arr = img_as_float(np.array(small))
    segments = slic(arr, n_segments=300, compactness=12, sigma=1,
                    start_label=0, channel_axis=2)

    h, w = segments.shape
    brightness = arr.mean(axis=2)

    if surface == "floor":
        r0, r1, c0, c1 = int(h * 0.70), h, 0, w
        valid = brightness < 0.82
    elif surface == "ceiling":
        r0, r1, c0, c1 = 0, int(h * 0.20), 0, w
        valid = brightness > 0.30
    else:
        r0, r1, c0, c1 = int(h * 0.15), int(h * 0.80), int(w * 0.08), int(w * 0.92)
        valid = (brightness > 0.12) & (brightness < 0.88)

    roi_mask = np.zeros((h, w), dtype=bool)
    roi_mask[r0:r1, c0:c1] = True
    roi_mask &= valid
    roi_labels = segments[roi_mask]
    if len(roi_labels) == 0:
        roi_labels = segments[r0:r1, c0:c1].flatten()

    dominant = int(np.bincount(roi_labels).argmax())
    dom_lab = _lab_mean(arr[segments == dominant])

    # Use BFS from dominant label (connected only)
    adj = _build_adjacency(segments)
    n_labels = int(segments.max()) + 1
    lab_means = {}
    for lbl in range(n_labels):
        px = arr[segments == lbl]
        if len(px):
            lab_means[lbl] = _lab_mean(px)

    visited = {dominant}
    queue = deque([dominant])
    selected = {dominant}
    THRESHOLD = 14

    while queue:
        lbl = queue.popleft()
        for nb in adj[lbl]:
            if nb in visited:
                continue
            visited.add(nb)
            nb_lab = lab_means.get(nb)
            if nb_lab is None:
                continue
            if float(np.linalg.norm(nb_lab - dom_lab)) < THRESHOLD:
                selected.add(nb)
                queue.append(nb)

    out = np.zeros((h, w), dtype=np.uint8)
    for lbl in selected:
        out[segments == lbl] = 255

    return Image.fromarray(out, mode="L").resize(pil.size, Image.NEAREST)


def _clean_mask(mask: Image.Image) -> Image.Image:
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=3))
    binary  = blurred.point(lambda p: 255 if p > 100 else 0)
    eroded  = binary.filter(ImageFilter.MinFilter(size=3))
    return eroded


@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data = request.get_json(force=True, silent=True) or {}
    image_b64     = data.get("image")
    surface_param = data.get("surface", "wall").lower().split(",")[0].strip()
    seed_x        = data.get("seed_x")
    seed_y        = data.get("seed_y")

    if not image_b64:
        return jsonify({"data": None, "error": "Missing image"}), 400
    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception:
        return jsonify({"data": None, "error": "Invalid base64"}), 400

    try:
        pil = Image.open(io.BytesIO(image_bytes))
        pil = ImageOps.exif_transpose(pil).convert("RGB")
    except Exception as e:
        return jsonify({"data": None, "error": f"Image decode failed: {e}"}), 500

    try:
        if seed_x is not None and seed_y is not None:
            raw    = _segment_flood(pil, float(seed_x), float(seed_y))
            method = "flood"
        else:
            raw    = _segment_auto(pil, surface_param)
            method = "auto"
        cleaned = _clean_mask(raw)
    except Exception as e:
        return jsonify({"data": None, "error": f"Segmentation failed: {e}"}), 500

    buf = io.BytesIO()
    cleaned.save(buf, format="PNG")
    mask_b64 = base64.b64encode(buf.getvalue()).decode()

    arr = np.array(cleaned)
    coverage = float((arr > 127).sum()) / arr.size

    return jsonify({
        "data": {
            "mask":     mask_b64,
            "surface":  surface_param,
            "coverage": round(coverage, 3),
            "method":   method,
        },
        "error": None,
    })
