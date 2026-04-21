"""
POST /api/ai-render
Uses OpenAI gpt-image-1 to paint a specific surface in a room photo.

Replaces the SAM2 mask + blend pipeline entirely.
OpenAI understands room geometry — no segmentation needed.

Request:
  image_b64   — base64 JPEG of the room
  surface     — "wall" | "ceiling" | "floor" | "trim"
  color_hex   — e.g. "#2C3E50"
  color_name  — e.g. "Navy Blue" (helps the model understand the color)

Response:
  { "data": { "rendered_b64": "...", "surface": "wall", "color_hex": "#2C3E50" } }
"""
import base64
import io
import os

from flask import Blueprint, jsonify, request
from PIL import Image, ImageOps

ai_render_bp = Blueprint("ai_render", __name__)

# Surface descriptions that help GPT understand exactly what to paint
_SURFACE_PROMPTS = {
    "wall": (
        "Paint ONLY the walls (the vertical painted surfaces on the sides of the room) "
        "with the color {color}. "
        "Do NOT change the ceiling, floor, trim, baseboards, furniture, artwork, "
        "doors, windows, or any other object. "
        "Keep the room's lighting, shadows, and reflections realistic."
    ),
    "ceiling": (
        "Paint ONLY the ceiling (the horizontal surface at the top of the room) "
        "with the color {color}. "
        "Do NOT change the walls, floor, trim, furniture, or any other surface. "
        "Keep lighting and shadows realistic."
    ),
    "floor": (
        "Paint ONLY the floor (the horizontal surface at the bottom that people walk on) "
        "with the color {color}. "
        "Do NOT change the walls, ceiling, furniture, rugs, or any other object. "
        "Keep lighting and shadows realistic."
    ),
    "trim": (
        "Paint ONLY the trim and baseboards (the narrow decorative strips along the "
        "bottom of the walls and around door/window frames) with the color {color}. "
        "Do NOT change the walls, ceiling, floor, furniture, or anything else. "
        "Keep lighting and shadows realistic."
    ),
}


def _hex_to_name(hex_code: str) -> str:
    """Convert hex to a readable color description for the prompt."""
    hex_code = hex_code.lstrip("#")
    r = int(hex_code[0:2], 16)
    g = int(hex_code[2:4], 16)
    b = int(hex_code[4:6], 16)
    # Simple hue description
    mx = max(r, g, b)
    mn = min(r, g, b)
    lightness = (mx + mn) / 2
    if mx == mn:
        hue = "gray"
    elif mx == r:
        hue = "red" if g < 128 else "orange" if g < 200 else "yellow"
    elif mx == g:
        hue = "green" if b < 128 else "teal"
    else:
        hue = "blue" if r < 128 else "purple"
    brightness = "dark" if lightness < 80 else "light" if lightness > 180 else "medium"
    return f"{brightness} {hue} (RGB {r},{g},{b})"


@ai_render_bp.route("/api/ai-render", methods=["POST"])
def ai_render():
    try:
        from openai import OpenAI

        data       = request.get_json(force=True, silent=True) or {}
        image_b64  = data.get("image_b64", "")
        surface    = data.get("surface", "wall").lower()
        color_hex  = data.get("color_hex", "#FFFFFF")
        color_name = data.get("color_name", "")

        if not image_b64:
            return jsonify({"error": "image_b64 required"}), 400
        if surface not in _SURFACE_PROMPTS:
            return jsonify({"error": f"surface must be one of {list(_SURFACE_PROMPTS)}"}), 400

        # Strip data-URL prefix
        if "," in image_b64:
            image_b64 = image_b64.split(",", 1)[1]

        # Decode + EXIF-correct + resize to 1024 (OpenAI limit)
        try:
            img_bytes = base64.b64decode(image_b64)
            pil = Image.open(io.BytesIO(img_bytes))
            pil = ImageOps.exif_transpose(pil).convert("RGBA")

            # Fit within 512×512 — faster OpenAI processing, no quality loss for painting
            pil.thumbnail((512, 512), Image.LANCZOS)

            buf = io.BytesIO()
            pil.save(buf, format="PNG")
            buf.seek(0)
        except Exception as e:
            return jsonify({"error": f"Image decode failed: {e}"}), 400

        # Build the prompt
        color_desc = color_name if color_name else _hex_to_name(color_hex)
        color_full = f"{color_desc} ({color_hex})"
        prompt     = _SURFACE_PROMPTS[surface].format(color=color_full)
        print(f"[ai-render] surface={surface} color={color_full}")
        print(f"[ai-render] prompt={prompt[:120]}...")

        # Call OpenAI image edit
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            return jsonify({"error": "OPENAI_API_KEY not configured"}), 500

        client = OpenAI(api_key=api_key)

        # gpt-image-1 requires a named file-like object (BytesIO needs a name attr)
        buf.name = "room.png"

        response = client.images.edit(
            model="gpt-image-1",
            image=buf,
            prompt=prompt,
        )

        # gpt-image-1 returns base64 data directly
        result_b64 = response.data[0].b64_json
        if not result_b64:
            # Fallback: download from URL if returned that way
            import requests as req
            url = response.data[0].url
            r   = req.get(url, timeout=60)
            result_b64 = base64.b64encode(r.content).decode()

        return jsonify({
            "data": {
                "rendered_b64": result_b64,
                "surface":      surface,
                "color_hex":    color_hex,
            },
            "error": None,
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
