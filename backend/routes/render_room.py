"""
PM-11: POST /render-room
Accepts room image + wall mask + target HEX + finish.
Calls Replicate SD-inpainting, polls for result, caches in Supabase Storage.
"""
import base64
import os
import time
import uuid

import replicate
import requests
from flask import Blueprint, request, jsonify

from utils.supabase_client import get_supabase
from utils.color_utils import is_valid_hex

render_room_bp = Blueprint("render_room", __name__)

BUCKET = "paintmatch-renders"
POLL_INTERVAL = 3   # seconds
MAX_POLLS = 30      # 90 seconds max


def _hex_to_prompt(hex_color: str, finish: str) -> str:
    """Build a Stable Diffusion inpainting prompt that describes the wall color and finish."""
    finish_desc = {
        "matte": "flat matte painted wall",
        "eggshell": "eggshell finish painted wall",
        "satin": "satin sheen painted wall",
        "gloss": "high-gloss painted wall",
    }.get(finish, "painted wall")
    return (
        f"interior room wall painted {hex_color} color, {finish_desc}, "
        "photorealistic, high quality, natural lighting, architectural photography"
    )


def _upload_to_supabase(image_bytes: bytes, filename: str) -> str:
    """Upload rendered PNG bytes to Supabase Storage and return public URL."""
    sb = get_supabase()
    sb.storage.from_(BUCKET).upload(
        path=filename,
        file=image_bytes,
        file_options={"content-type": "image/png"},
    )
    return sb.storage.from_(BUCKET).get_public_url(filename)


@render_room_bp.route("/render-room", methods=["POST"])
def render_room():
    data = request.get_json(force=True, silent=True) or {}

    image_b64 = data.get("image")       # base64-encoded original room image
    mask_b64 = data.get("wall_mask")    # base64-encoded binary wall mask
    target_hex = data.get("target_hex", "").strip()
    finish = data.get("finish", "matte").lower()

    if not image_b64 or not mask_b64:
        return jsonify({"data": None, "error": "Missing image or wall_mask"}), 400
    if not is_valid_hex(target_hex):
        return jsonify({"data": None, "error": "Invalid target_hex"}), 400
    if finish not in {"matte", "eggshell", "satin", "gloss"}:
        finish = "matte"

    # Decode base64 → bytes and wrap as data URIs for Replicate
    try:
        image_bytes = base64.b64decode(image_b64)
        mask_bytes = base64.b64decode(mask_b64)
    except Exception:
        return jsonify({"data": None, "error": "Invalid base64 data"}), 400

    image_uri = "data:image/jpeg;base64," + base64.b64encode(image_bytes).decode()
    mask_uri = "data:image/png;base64," + base64.b64encode(mask_bytes).decode()
    prompt = _hex_to_prompt(target_hex, finish)

    try:
        # Start async prediction
        prediction = replicate.predictions.create(
            version="stability-ai/stable-diffusion-inpainting:95b7223104132402a9ae91cc677285bc5eb997834bd2349fa486f53910fd68b3",
            input={
                "prompt": prompt,
                "image": image_uri,
                "mask": mask_uri,
                "num_inference_steps": 30,
                "guidance_scale": 7.5,
            },
        )

        # Poll until complete
        for _ in range(MAX_POLLS):
            prediction = replicate.predictions.get(prediction.id)
            if prediction.status == "succeeded":
                break
            if prediction.status in {"failed", "canceled"}:
                return jsonify({"data": None, "error": f"Replicate job {prediction.status}"}), 502
            time.sleep(POLL_INTERVAL)
        else:
            return jsonify({"data": None, "error": "Replicate job timed out"}), 504

        output_url = prediction.output[0] if isinstance(prediction.output, list) else prediction.output

        # Download rendered image and cache in Supabase Storage
        rendered_bytes = requests.get(output_url, timeout=30).content
        filename = f"{uuid.uuid4()}.png"
        cached_url = _upload_to_supabase(rendered_bytes, filename)

        return jsonify({
            "data": {
                "rendered_image_url": cached_url,
                "target_hex": target_hex,
                "finish": finish,
            },
            "error": None,
        })

    except replicate.exceptions.ReplicateError as e:
        return jsonify({"data": None, "error": f"Replicate error: {e}"}), 502
    except Exception as e:
        return jsonify({"data": None, "error": str(e)}), 500
