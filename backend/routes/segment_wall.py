"""
PM-11b: POST /segment-wall
Runs nvidia/segformer-b0-finetuned-ade-512-512 locally via transformers.
No external API — model is downloaded once and cached on startup.
Returns a base64 PNG mask — white = target surface, black = everything else.
"""
import base64
import io
import os

import numpy as np
from flask import Blueprint, jsonify, request
from PIL import Image, ImageChops, ImageFilter, ImageOps

segment_wall_bp = Blueprint("segment_wall", __name__)

# ADE20K label→index mapping for the surfaces we care about
# Full list: https://huggingface.co/nvidia/segformer-b0-finetuned-ade-512-512
ADE20K_LABELS = {
    "wall": 0,
    "floor": 3,
    "ceiling": 5,
}

# Lazy-loaded model — loaded once on first request
_pipeline = None

def _get_pipeline():
    global _pipeline
    if _pipeline is None:
        from transformers import pipeline as hf_pipeline
        _pipeline = hf_pipeline(
            "image-segmentation",
            model="nvidia/segformer-b0-finetuned-ade-512-512",
            device=-1,  # CPU
        )
    return _pipeline


def _combine_masks(segments: list, target_labels: set, orig_size: tuple) -> Image.Image:
    """OR-combine all masks for target_labels into a single L-mode image at orig_size."""
    combined = Image.new("L", orig_size, 0)
    for seg in segments:
        label = seg.get("label", "").lower()
        if label not in target_labels:
            continue
        mask_pil = seg.get("mask")  # transformers pipeline returns PIL Image
        if mask_pil is None:
            continue
        # Resize to original image size if needed
        if mask_pil.size != orig_size:
            mask_pil = mask_pil.resize(orig_size, Image.NEAREST)
        gray = mask_pil.convert("L")
        thresholded = gray.point(lambda p: 255 if p > 127 else 0)
        combined = ImageChops.lighter(combined, thresholded)
    return combined


def _clean_mask(mask: Image.Image) -> Image.Image:
    """Blur → re-threshold → erode to remove noise and soften edges."""
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=2))
    binary = blurred.point(lambda p: 255 if p > 80 else 0)
    eroded = binary.filter(ImageFilter.MinFilter(size=5))
    return eroded


@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data = request.get_json(force=True, silent=True) or {}

    image_b64 = data.get("image")
    surface_param = data.get("surface", "wall").lower()
    target_labels = {s.strip() for s in surface_param.split(",")}

    if not image_b64:
        return jsonify({"data": None, "error": "Missing image"}), 400

    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception:
        return jsonify({"data": None, "error": "Invalid base64"}), 400

    # Correct EXIF rotation
    try:
        pil = Image.open(io.BytesIO(image_bytes))
        pil = ImageOps.exif_transpose(pil).convert("RGB")
        orig_size = pil.size  # (width, height)
    except Exception as e:
        return jsonify({"data": None, "error": f"Image processing failed: {e}"}), 500

    # Run segmentation
    try:
        pipe = _get_pipeline()
        segments = pipe(pil)  # returns list of {label, score, mask (PIL Image)}
    except Exception as e:
        return jsonify({"data": None, "error": f"Segmentation failed: {e}"}), 502

    if not segments:
        return jsonify({"data": None, "error": "No segments returned"}), 502

    # Build + clean mask
    combined = _combine_masks(segments, target_labels, orig_size)
    cleaned = _clean_mask(combined)

    out_buf = io.BytesIO()
    cleaned.save(out_buf, format="PNG")
    mask_b64 = base64.b64encode(out_buf.getvalue()).decode()

    mask_arr = np.array(cleaned)
    coverage = float((mask_arr > 127).sum()) / mask_arr.size

    return jsonify({
        "data": {
            "mask": mask_b64,
            "surface": surface_param,
            "coverage": round(coverage, 3),
            "segments_found": [s.get("label") for s in segments],
        },
        "error": None,
    })
