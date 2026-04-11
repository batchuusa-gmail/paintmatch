"""
POST /segment-wall
Uses Meta SAM 2 via Replicate (meta/sam-2).
Strategy: run SAM auto-segmentation → get all individual masks →
pick the mask whose area covers the user's tap point (seed_x, seed_y).
This gives professional-quality, edge-accurate segmentation.
Falls back to BFS if Replicate fails.
"""
import base64
import io
import os
from collections import deque

import numpy as np
import requests as req
from flask import Blueprint, jsonify, request
from PIL import Image, ImageFilter, ImageOps

segment_wall_bp = Blueprint("segment_wall", __name__)

SAM2_VERSION = "fe97b453a6455861e3bac769b441ca1f1086110da7466dbb65cf1eecfd60dc83"
WORK_SIZE    = 1024  # longest edge — SAM works best at higher res


def _resize_to(pil: Image.Image, max_edge: int) -> Image.Image:
    w, h = pil.size
    scale = min(1.0, max_edge / max(w, h))
    if scale < 1.0:
        return pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    return pil


def _upload_to_replicate(pil: Image.Image, token: str) -> str:
    """Upload image bytes to Replicate file API, return URL."""
    buf = io.BytesIO()
    pil.save(buf, format="JPEG", quality=92)
    buf.seek(0)
    resp = req.post(
        "https://api.replicate.com/v1/files",
        headers={"Authorization": f"Bearer {token}"},
        files={"content": ("image.jpg", buf, "image/jpeg")},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["urls"]["get"]


def _sam_segment(pil: Image.Image, seed_x: float, seed_y: float) -> Image.Image:
    """
    1. Upload image to Replicate.
    2. Run SAM 2 auto-segmentation (returns individual_masks).
    3. Pick the mask that contains pixel (seed_x*W, seed_y*H).
    4. Return that mask resized to original pil size.
    """
    import replicate

    token = os.environ.get("REPLICATE_API_TOKEN") or os.environ.get("REPLICATE_API_KEY")
    if not token:
        raise RuntimeError("REPLICATE_API_TOKEN not set")

    work = _resize_to(pil, WORK_SIZE)
    image_url = _upload_to_replicate(work, token)

    client = replicate.Client(api_token=token)
    output = client.run(
        f"meta/sam-2:{SAM2_VERSION}",
        input={
            "image":                  image_url,
            "points_per_side":        32,
            "pred_iou_thresh":        0.88,
            "stability_score_thresh": 0.92,
            "use_m2m":                True,
        },
    )

    individual_masks = output.get("individual_masks", [])
    if not individual_masks:
        raise RuntimeError("SAM returned no masks")

    # Tap point in work-image pixel coords
    ww, wh = work.size
    tx = int(seed_x * ww)
    ty = int(seed_y * wh)

    # Download all masks, find ones that cover the tap point
    candidates = []   # (area, mask_pil)
    all_masks  = []   # (area, mask_pil) — for centroid fallback

    for mask_url in individual_masks:
        resp = req.get(str(mask_url), timeout=30)
        resp.raise_for_status()
        m = Image.open(io.BytesIO(resp.content)).convert("L")
        if m.size != work.size:
            m = m.resize(work.size, Image.NEAREST)
        arr = np.array(m)
        area = int((arr > 127).sum())
        all_masks.append((area, m))
        if arr[ty, tx] > 127:
            candidates.append((area, m))

    # Among masks that cover the tap, pick the LARGEST one.
    # Walls are large surfaces; switches/outlets are tiny objects in front of walls.
    # The largest mask at the tap point is almost always the wall/ceiling/floor.
    best_mask_pil = None
    best_area     = None
    if candidates:
        # Sort by area descending, take the largest
        candidates.sort(key=lambda x: x[0], reverse=True)
        best_area, best_mask_pil = candidates[0]

    if best_mask_pil is None:
        # No mask covers the tap → pick the largest mask whose centroid is closest
        best_dist = float("inf")
        for area, m in all_masks:
            arr = np.array(m)
            ys, xs = np.where(arr > 127)
            if len(xs) == 0:
                continue
            cx, cy = float(xs.mean()), float(ys.mean())
            dist = ((cx - tx) ** 2 + (cy - ty) ** 2) ** 0.5
            if dist < best_dist:
                best_dist = dist
                best_mask_pil = m

    if best_mask_pil is None:
        raise RuntimeError("Could not select a mask from SAM output")

    # Resize back to original image resolution
    return best_mask_pil.resize(pil.size, Image.NEAREST)


# ─── BFS fallback ────────────────────────────────────────────────────────────

def _segment_bfs(pil: Image.Image, seed_x: float, seed_y: float) -> Image.Image:
    from skimage.segmentation import slic
    from skimage.util import img_as_float
    from skimage.color import rgb2lab

    w, h = pil.size
    scale = 512 / max(w, h)
    small = pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    arr   = img_as_float(np.array(small))
    segs  = slic(arr, n_segments=300, compactness=12, sigma=1,
                 start_label=0, channel_axis=2)
    sh, sw = segs.shape

    sy = max(0, min(int(seed_y * sh), sh - 1))
    sx = max(0, min(int(seed_x * sw), sw - 1))
    seed_lbl = int(segs[sy, sx])

    n = int(segs.max()) + 1

    def lab_mean(lbl):
        px = arr[segs == lbl]
        return rgb2lab(px.mean(axis=0).reshape(1, 1, 3)).reshape(3) if len(px) else None

    # Build adjacency
    adj = {i: set() for i in range(n)}
    for r in range(sh):
        for c in range(sw):
            lbl = int(segs[r, c])
            for dr, dc in ((0, 1), (1, 0)):
                nr, nc = r + dr, c + dc
                if 0 <= nr < sh and 0 <= nc < sw:
                    nb = int(segs[nr, nc])
                    if nb != lbl:
                        adj[lbl].add(nb); adj[nb].add(lbl)

    seed_lab = lab_mean(seed_lbl)
    visited  = {seed_lbl}
    queue    = deque([seed_lbl])
    selected = {seed_lbl}

    while queue:
        lbl = queue.popleft()
        for nb in adj[lbl]:
            if nb in visited:
                continue
            visited.add(nb)
            nb_lab = lab_mean(nb)
            if nb_lab is not None and np.linalg.norm(nb_lab - seed_lab) < 14:
                selected.add(nb); queue.append(nb)

    out = np.zeros((sh, sw), dtype=np.uint8)
    for lbl in selected:
        out[segs == lbl] = 255
    return Image.fromarray(out, "L").resize(pil.size, Image.NEAREST)


def _segment_auto(pil: Image.Image, surface: str) -> Image.Image:
    from skimage.segmentation import slic
    from skimage.util import img_as_float
    from skimage.color import rgb2lab

    w, h = pil.size
    scale = 512 / max(w, h)
    small = pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    arr   = img_as_float(np.array(small))
    segs  = slic(arr, n_segments=300, compactness=12, sigma=1,
                 start_label=0, channel_axis=2)
    sh, sw = segs.shape
    br = arr.mean(axis=2)

    if surface == "floor":
        r0, r1, c0, c1 = int(sh * .70), sh, 0, sw
        valid = br < 0.82
    elif surface == "ceiling":
        r0, r1, c0, c1 = 0, int(sh * .20), 0, sw
        valid = br > 0.30
    else:
        r0, r1, c0, c1 = int(sh * .15), int(sh * .80), int(sw * .08), int(sw * .92)
        valid = (br > 0.12) & (br < 0.88)

    roi = np.zeros((sh, sw), dtype=bool)
    roi[r0:r1, c0:c1] = True; roi &= valid
    labels = segs[roi]
    if not len(labels):
        labels = segs[r0:r1, c0:c1].flatten()

    dominant = int(np.bincount(labels).argmax())
    dom_lab  = rgb2lab(arr[segs == dominant].mean(axis=0).reshape(1, 1, 3)).reshape(3)

    out = np.zeros((sh, sw), dtype=np.uint8)
    for lbl in range(int(segs.max()) + 1):
        px = arr[segs == lbl]
        if not len(px):
            continue
        lab = rgb2lab(px.mean(axis=0).reshape(1, 1, 3)).reshape(3)
        if np.linalg.norm(lab - dom_lab) < 14:
            out[segs == lbl] = 255

    return Image.fromarray(out, "L").resize(pil.size, Image.NEAREST)


def _clean(mask: Image.Image) -> Image.Image:
    b = mask.filter(ImageFilter.GaussianBlur(radius=3))
    b = b.point(lambda p: 255 if p > 100 else 0)
    return b.filter(ImageFilter.MinFilter(size=3))


# ─── Route ───────────────────────────────────────────────────────────────────

@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data          = request.get_json(force=True, silent=True) or {}
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

    method = "auto"
    try:
        if seed_x is not None and seed_y is not None:
            sx, sy = float(seed_x), float(seed_y)
            try:
                raw    = _sam_segment(pil, sx, sy)
                method = "sam2"
            except Exception as e:
                print(f"[segment-wall] SAM failed ({e}), BFS fallback")
                raw    = _segment_bfs(pil, sx, sy)
                method = "bfs_fallback"
        else:
            raw    = _segment_auto(pil, surface_param)
            method = "auto"
        cleaned = _clean(raw)
    except Exception as e:
        return jsonify({"data": None, "error": f"Segmentation failed: {e}"}), 500

    buf = io.BytesIO()
    cleaned.save(buf, format="PNG")
    mask_b64 = base64.b64encode(buf.getvalue()).decode()
    arr      = np.array(cleaned)
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
