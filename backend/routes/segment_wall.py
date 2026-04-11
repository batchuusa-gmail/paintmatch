"""
PM-11b: POST /segment-wall
Uses HuggingFace Inference API (SegFormer ADE20K) to detect wall pixels.
Returns a base64 PNG mask — white = target surface, black = everything else.
Improvements:
- Morphological erosion to clean mask edges and remove noise
- Multi-surface support (comma-separated surfaces)
- Mask returned at original image resolution
"""
import base64
import io
import os

import numpy as np
import requests
from flask import Blueprint, jsonify, request
from PIL import Image, ImageChops, ImageFilter, ImageOps

segment_wall_bp = Blueprint("segment_wall", __name__)

HF_API_URL = "https://api-inference.huggingface.co/models/nvidia/segformer-b0-finetuned-ade-512-512"


def _call_hf_segmentation(image_bytes: bytes) -> list:
    hf_token = os.environ.get("HF_TOKEN", "").strip()
    headers = {"Authorization": f"Bearer {hf_token}"} if hf_token else {}
    resp = requests.post(HF_API_URL, headers=headers, data=image_bytes, timeout=45)
    resp.raise_for_status()
    return resp.json()


def _combine_masks(segments: list, target_labels: set, size: tuple) -> Image.Image:
    """OR-combine all masks for target_labels into a single L-mode image."""
    combined = Image.new("L", size, 0)
    for seg in segments:
        label = seg.get("label", "").lower()
        if label not in target_labels:
            continue
        mask_b64 = seg.get("mask", "")
        if not mask_b64:
            continue
        mask_bytes = base64.b64decode(mask_b64)
        mask_img = Image.open(io.BytesIO(mask_bytes)).convert("L")
        # Resize to original image size (SegFormer outputs 512x512)
        if mask_img.size != size:
            mask_img = mask_img.resize(size, Image.NEAREST)
        thresholded = mask_img.point(lambda p: 255 if p > 127 else 0)
        combined = ImageChops.lighter(combined, thresholded)
    return combined


def _clean_mask(mask: Image.Image) -> Image.Image:
    """
    Post-process mask:
    1. Slight blur to soften jagged SegFormer edges
    2. Re-threshold to keep it binary
    3. Erosion (shrink by 2px) to remove thin noise at object boundaries
    """
    # Soften edges
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=2))
    # Re-binarize
    binary = blurred.point(lambda p: 255 if p > 80 else 0)
    # Erosion: MIN filter shrinks white regions, removes 1-2px noise
    eroded = binary.filter(ImageFilter.MinFilter(size=5))
    return eroded


@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data = request.get_json(force=True, silent=True) or {}

    image_b64 = data.get("image")
    # Accept single string "wall" or comma-separated "wall,ceiling"
    surface_param = data.get("surface", "wall").lower()
    target_labels = {s.strip() for s in surface_param.split(",")}

    if not image_b64:
        return jsonify({"data": None, "error": "Missing image"}), 400

    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception:
        return jsonify({"data": None, "error": "Invalid base64"}), 400

    # Correct EXIF rotation, keep original size for mask output
    try:
        pil = Image.open(io.BytesIO(image_bytes))
        pil = ImageOps.exif_transpose(pil).convert("RGB")
        orig_size = pil.size  # (width, height) — mask returned at this size

        buf = io.BytesIO()
        pil.save(buf, format="JPEG", quality=85)
        image_bytes_corrected = buf.getvalue()
    except Exception as e:
        return jsonify({"data": None, "error": f"Image processing failed: {e}"}), 500

    try:
        segments = _call_hf_segmentation(image_bytes_corrected)
    except Exception as e:
        return jsonify({"data": None, "error": f"Segmentation failed: {e}"}), 502

    if not isinstance(segments, list) or not segments:
        return jsonify({"data": None, "error": "No segments returned from model"}), 502

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
