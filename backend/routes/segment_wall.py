"""
POST /segment-wall
SLIC superpixels + brightness-filtered spatial prior.
Returns base64 PNG mask — white = target surface, black = everything else.
"""
import base64
import io

import numpy as np
from flask import Blueprint, jsonify, request
from PIL import Image, ImageFilter, ImageOps

segment_wall_bp = Blueprint("segment_wall", __name__)


def _segment(pil: Image.Image, surface: str) -> Image.Image:
    from skimage.segmentation import slic
    from skimage.util import img_as_float

    W, H = pil.size
    work_w, work_h = min(W, 512), min(H, 512)
    small = pil.resize((work_w, work_h), Image.BILINEAR)
    arr = img_as_float(np.array(small))  # (H, W, 3) float64
    brightness = arr.mean(axis=2)        # (H, W)

    segments = slic(arr, n_segments=200, compactness=10, sigma=1,
                    start_label=0, channel_axis=2)
    h, w = segments.shape

    # Spatial ROI per surface
    if surface == "floor":
        r0, r1, c0, c1 = int(h * 0.65), h, 0, w
    elif surface == "ceiling":
        r0, r1, c0, c1 = 0, int(h * 0.22), 0, w
    else:  # wall
        r0, r1, c0, c1 = int(h * 0.15), int(h * 0.80), int(w * 0.05), int(w * 0.95)

    # Exclude very bright (windows/tablecloth) and very dark (shadow/furniture)
    if surface == "wall":
        valid = (brightness > 0.10) & (brightness < 0.90)
    elif surface == "ceiling":
        valid = brightness > 0.30          # ceilings are light
    else:  # floor
        valid = brightness < 0.80          # floors tend to be darker

    roi_mask = np.zeros((h, w), dtype=bool)
    roi_mask[r0:r1, c0:c1] = True
    roi_mask &= valid

    roi_labels = segments[roi_mask]
    if len(roi_labels) == 0:
        roi_labels = segments[r0:r1, c0:c1].flatten()  # fallback without brightness filter

    dominant = int(np.bincount(roi_labels).argmax())

    dom_pixels = arr[segments == dominant]
    dom_mean = dom_pixels.mean(axis=0)

    # Include superpixels whose average color is within threshold of dominant
    n_labels = int(segments.max()) + 1
    out_mask = np.zeros((h, w), dtype=np.uint8)
    for lbl in range(n_labels):
        px = arr[segments == lbl]
        if len(px) == 0:
            continue
        # Exclude superpixels that are very bright (white objects) or very dark
        seg_brightness = px.mean(axis=0).mean()
        if surface == "wall" and (seg_brightness > 0.88 or seg_brightness < 0.10):
            continue
        dist = float(np.linalg.norm(px.mean(axis=0) - dom_mean))
        if dist < 0.14:
            out_mask[segments == lbl] = 255

    return Image.fromarray(out_mask, mode="L").resize(pil.size, Image.NEAREST)


def _clean_mask(mask: Image.Image) -> Image.Image:
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=3))
    binary  = blurred.point(lambda p: 255 if p > 100 else 0)
    eroded  = binary.filter(ImageFilter.MinFilter(size=5))
    return eroded


@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data = request.get_json(force=True, silent=True) or {}
    image_b64     = data.get("image")
    surface_param = data.get("surface", "wall").lower().split(",")[0].strip()

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
        raw     = _segment(pil, surface_param)
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
            "method":   "slic",
        },
        "error": None,
    })
