"""
POST /segment-wall
Segments walls/ceiling/floor using SLIC superpixels (scikit-image) +
spatial position heuristics. No heavy ML deps — works on any Railway tier.
Returns a base64 PNG mask — white = target surface, black = everything else.
"""
import base64
import io

import numpy as np
from flask import Blueprint, jsonify, request
from PIL import Image, ImageFilter, ImageOps
from skimage.segmentation import slic
from skimage.util import img_as_float

segment_wall_bp = Blueprint("segment_wall", __name__)


def _segment(pil: Image.Image, surface: str) -> Image.Image:
    """
    SLIC superpixel segmentation + spatial prior.

    Strategy per surface:
      wall    — dominant color cluster in the middle 60% height band
      floor   — dominant cluster in the bottom 30%
      ceiling — dominant cluster in the top 20%
    """
    W, H = pil.size
    work_w, work_h = min(W, 512), min(H, 512)
    small = pil.resize((work_w, work_h), Image.BILINEAR)
    arr = img_as_float(np.array(small))           # (H, W, 3) float64

    # SLIC superpixels — ~200 segments, compact so they respect color borders
    segments = slic(arr, n_segments=200, compactness=10, sigma=1,
                    start_label=0, channel_axis=2)

    h, w = segments.shape

    # Define the spatial ROI for each surface
    if surface == "floor":
        row_lo, row_hi = int(h * 0.65), h
        col_lo, col_hi = 0, w
    elif surface == "ceiling":
        row_lo, row_hi = 0, int(h * 0.22)
        col_lo, col_hi = 0, w
    else:  # wall (default)
        row_lo, row_hi = int(h * 0.15), int(h * 0.80)
        col_lo, col_hi = int(w * 0.05), int(w * 0.95)

    roi_labels = segments[row_lo:row_hi, col_lo:col_hi].flatten()
    if len(roi_labels) == 0:
        roi_labels = segments.flatten()

    # Most frequent superpixel label in the ROI → that's our target region
    dominant = int(np.bincount(roi_labels).argmax())

    # Expand: include all superpixels whose average color is close to dominant
    dom_pixels = arr[segments == dominant]
    dom_mean = dom_pixels.mean(axis=0)                  # (3,) RGB mean

    n_labels = segments.max() + 1
    mask = np.zeros((h, w), dtype=np.uint8)
    for lbl in range(n_labels):
        px = arr[segments == lbl]
        if len(px) == 0:
            continue
        dist = np.linalg.norm(px.mean(axis=0) - dom_mean)
        if dist < 0.12:                                  # color distance threshold
            mask[segments == lbl] = 255

    mask_pil = Image.fromarray(mask, mode="L").resize(pil.size, Image.NEAREST)
    return mask_pil


def _clean_mask(mask: Image.Image) -> Image.Image:
    """Blur → re-threshold → erode to smooth edges and reduce noise."""
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=3))
    binary  = blurred.point(lambda p: 255 if p > 100 else 0)
    eroded  = binary.filter(ImageFilter.MinFilter(size=5))
    return eroded


@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data = request.get_json(force=True, silent=True) or {}

    image_b64    = data.get("image")
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
        raw    = _segment(pil, surface_param)
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
