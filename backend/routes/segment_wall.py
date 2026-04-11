"""
POST /segment-wall
Professional tap-to-paint segmentation:
  - If seed_x / seed_y provided (0–1 fractions): SLIC + seed-label expansion
    User tapped the surface → we expand from that exact point to similar regions.
  - If no seed: spatial heuristic fallback (automatic mode).
Returns base64 PNG mask — white = target surface, black = everything else.
"""
import base64
import io

import numpy as np
from flask import Blueprint, jsonify, request
from PIL import Image, ImageFilter, ImageOps

segment_wall_bp = Blueprint("segment_wall", __name__)

WORK_SIZE = 512   # resize longest edge to this before segmentation


def _resize_keep_aspect(pil: Image.Image) -> tuple[Image.Image, float]:
    """Resize so longest edge = WORK_SIZE. Returns (resized, scale_factor)."""
    w, h = pil.size
    scale = WORK_SIZE / max(w, h)
    new_w, new_h = int(w * scale), int(h * scale)
    return pil.resize((new_w, new_h), Image.BILINEAR), scale


def _run_slic(arr):
    from skimage.segmentation import slic
    from skimage.util import img_as_float
    if arr.dtype != float:
        arr = img_as_float(arr)
    return slic(arr, n_segments=400, compactness=8, sigma=1,
                start_label=0, channel_axis=2), arr


def _segment_from_seed(pil: Image.Image, seed_x: float, seed_y: float) -> Image.Image:
    """
    User tapped (seed_x, seed_y) — find the superpixel there and expand to
    all superpixels with a similar color. This is how professional apps work.
    """
    small, _ = _resize_keep_aspect(pil)
    arr_raw = np.array(small)
    segments, arr = _run_slic(arr_raw)

    h, w = segments.shape
    sy = int(seed_y * h)
    sx = int(seed_x * w)
    sy = max(0, min(sy, h - 1))
    sx = max(0, min(sx, w - 1))

    seed_label = int(segments[sy, sx])
    seed_color = arr[segments == seed_label].mean(axis=0)   # (3,) float

    # Expand: include superpixels whose mean color is close to seed_color
    # Use LAB-space distance for perceptual accuracy
    from skimage.color import rgb2lab
    seed_lab = rgb2lab(seed_color.reshape(1, 1, 3)).reshape(3)

    n_labels = int(segments.max()) + 1
    out = np.zeros((h, w), dtype=np.uint8)
    for lbl in range(n_labels):
        px = arr[segments == lbl]
        if len(px) == 0:
            continue
        mean_rgb = px.mean(axis=0).reshape(1, 1, 3)
        mean_lab = rgb2lab(mean_rgb).reshape(3)
        delta_e = float(np.linalg.norm(mean_lab - seed_lab))
        if delta_e < 18:          # perceptual color distance threshold
            out[segments == lbl] = 255

    return Image.fromarray(out, mode="L").resize(pil.size, Image.NEAREST)


def _segment_auto(pil: Image.Image, surface: str) -> Image.Image:
    """Automatic spatial heuristic fallback when no seed is given."""
    small, _ = _resize_keep_aspect(pil)
    arr_raw = np.array(small)
    segments, arr = _run_slic(arr_raw)

    h, w = segments.shape
    brightness = arr.mean(axis=2)

    if surface == "floor":
        r0, r1, c0, c1 = int(h * 0.65), h, 0, w
        valid = brightness < 0.80
    elif surface == "ceiling":
        r0, r1, c0, c1 = 0, int(h * 0.22), 0, w
        valid = brightness > 0.30
    else:  # wall
        r0, r1, c0, c1 = int(h * 0.15), int(h * 0.80), int(w * 0.05), int(w * 0.95)
        valid = (brightness > 0.10) & (brightness < 0.90)

    roi_mask = np.zeros((h, w), dtype=bool)
    roi_mask[r0:r1, c0:c1] = True
    roi_mask &= valid

    roi_labels = segments[roi_mask]
    if len(roi_labels) == 0:
        roi_labels = segments[r0:r1, c0:c1].flatten()

    dominant = int(np.bincount(roi_labels).argmax())
    dom_color = arr[segments == dominant].mean(axis=0)

    from skimage.color import rgb2lab
    dom_lab = rgb2lab(dom_color.reshape(1, 1, 3)).reshape(3)

    n_labels = int(segments.max()) + 1
    out = np.zeros((h, w), dtype=np.uint8)
    for lbl in range(n_labels):
        px = arr[segments == lbl]
        if len(px) == 0:
            continue
        seg_brightness = float(px.mean())
        if surface == "wall" and (seg_brightness > 0.88 or seg_brightness < 0.10):
            continue
        mean_lab = rgb2lab(px.mean(axis=0).reshape(1, 1, 3)).reshape(3)
        if float(np.linalg.norm(mean_lab - dom_lab)) < 18:
            out[segments == lbl] = 255

    return Image.fromarray(out, mode="L").resize(pil.size, Image.NEAREST)


def _clean_mask(mask: Image.Image) -> Image.Image:
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=4))
    binary  = blurred.point(lambda p: 255 if p > 100 else 0)
    eroded  = binary.filter(ImageFilter.MinFilter(size=5))
    return eroded


@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data = request.get_json(force=True, silent=True) or {}
    image_b64     = data.get("image")
    surface_param = data.get("surface", "wall").lower().split(",")[0].strip()
    seed_x        = data.get("seed_x")   # float 0–1 or None
    seed_y        = data.get("seed_y")   # float 0–1 or None

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
            raw = _segment_from_seed(pil, float(seed_x), float(seed_y))
            method = "seed"
        else:
            raw = _segment_auto(pil, surface_param)
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
