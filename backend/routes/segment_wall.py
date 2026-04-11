"""
PM-11b: POST /segment-wall
Uses HuggingFace Inference API (SegFormer ADE20K) to detect wall pixels.
Returns a base64 PNG mask — white = wall, black = everything else.
"""
import base64
import io
import os

import requests
from flask import Blueprint, jsonify, request
from PIL import Image

segment_wall_bp = Blueprint("segment_wall", __name__)

HF_API_URL = "https://api-inference.huggingface.co/models/nvidia/segformer-b0-finetuned-ade-512-512"

# ADE20K labels that count as "wall" surface (things we want to paint)
WALL_LABELS = {"wall", "ceiling", "floor"}  # user can select which via param


def _call_hf_segmentation(image_bytes: bytes) -> list:
    """Call HuggingFace Inference API and return list of segments."""
    hf_token = os.environ.get("HF_TOKEN", "").strip()
    headers = {}
    if hf_token:
        headers["Authorization"] = f"Bearer {hf_token}"

    resp = requests.post(HF_API_URL, headers=headers, data=image_bytes, timeout=30)
    resp.raise_for_status()
    return resp.json()


def _combine_masks(segments: list, target_labels: set, size: tuple) -> Image.Image:
    """Combine all masks matching target_labels into a single white/black PNG."""
    from PIL import Image as PILImage
    combined = PILImage.new("L", size, 0)  # black base
    for seg in segments:
        label = seg.get("label", "").lower()
        if label in target_labels:
            # HF returns mask as base64-encoded PNG
            mask_b64 = seg.get("mask", "")
            if not mask_b64:
                continue
            mask_bytes = base64.b64decode(mask_b64)
            mask_img = PILImage.open(io.BytesIO(mask_bytes)).convert("L")
            # Threshold: any non-zero pixel = wall
            thresholded = mask_img.point(lambda p: 255 if p > 127 else 0)
            # Merge into combined (OR operation)
            from PIL import ImageChops
            combined = ImageChops.lighter(combined, thresholded)
    return combined


@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data = request.get_json(force=True, silent=True) or {}

    image_b64 = data.get("image")
    # "wall", "ceiling", "floor" — default to wall only
    surface = data.get("surface", "wall").lower()

    if not image_b64:
        return jsonify({"data": None, "error": "Missing image"}), 400

    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception:
        return jsonify({"data": None, "error": "Invalid base64"}), 400

    # Correct EXIF rotation and convert to JPEG for HF API
    try:
        from PIL import ImageOps
        pil = Image.open(io.BytesIO(image_bytes))
        pil = ImageOps.exif_transpose(pil).convert("RGB")
        orig_size = pil.size  # (width, height)

        buf = io.BytesIO()
        pil.save(buf, format="JPEG", quality=85)
        image_bytes_corrected = buf.getvalue()
    except Exception as e:
        return jsonify({"data": None, "error": f"Image processing failed: {e}"}), 500

    # Determine which labels to include
    target_labels = {surface}  # "wall", "ceiling", or "floor"

    try:
        segments = _call_hf_segmentation(image_bytes_corrected)
    except Exception as e:
        return jsonify({"data": None, "error": f"Segmentation failed: {e}"}), 502

    if not isinstance(segments, list) or len(segments) == 0:
        return jsonify({"data": None, "error": "No segments returned"}), 502

    # Build combined mask at original image resolution
    combined = _combine_masks(segments, target_labels, orig_size)

    # Encode mask as base64 PNG
    out_buf = io.BytesIO()
    combined.save(out_buf, format="PNG")
    mask_b64 = base64.b64encode(out_buf.getvalue()).decode()

    # Count wall pixel coverage
    import numpy as np
    mask_arr = np.array(combined)
    coverage = float((mask_arr > 127).sum()) / mask_arr.size

    return jsonify({
        "data": {
            "mask": mask_b64,
            "surface": surface,
            "coverage": round(coverage, 3),
            "segments_found": [s.get("label") for s in segments],
        },
        "error": None,
    })
