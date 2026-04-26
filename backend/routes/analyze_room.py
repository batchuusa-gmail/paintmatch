"""
PM-10: POST /analyze-room
Accepts a room image, sends to GPT-4o vision, returns structured palette JSON.
"""
import base64
import os
import json
import io

from openai import OpenAI
from flask import Blueprint, request, jsonify
from PIL import Image

analyze_room_bp = Blueprint("analyze_room", __name__)

_openai_client: OpenAI | None = None


def _get_client() -> OpenAI:
    global _openai_client
    if _openai_client is None:
        _openai_client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    return _openai_client


USER_PROMPT = """Analyze this room photo. Return a JSON object with exactly this shape:
{
  "wall_hex": "#RRGGBB",
  "room_style": "modern|traditional|farmhouse|scandinavian|bohemian|industrial|coastal|other",
  "lighting": "bright_natural|warm_natural|cool_natural|artificial_warm|artificial_cool|mixed|dim",
  "furniture_palette": ["#RRGGBB"],
  "recommended_palettes": [
    {
      "name": "Palette name",
      "hex": "#RRGGBB",
      "rationale": "One sentence why this color works for this room."
    }
  ]
}
Rules:
- recommended_palettes must have exactly 3 entries.
- All hex values must be valid 6-digit hex codes including the #.
- Return nothing except the JSON object.
"""


@analyze_room_bp.route("/analyze-room", methods=["POST"])
def analyze_room():
    if "image" not in request.files:
        return jsonify({"data": None, "error": "Missing image file"}), 400

    image_file = request.files["image"]
    if image_file.filename == "":
        return jsonify({"data": None, "error": "Empty filename"}), 400

    raw_bytes = image_file.read()

    # Convert any format (HEIC, BMP, TIFF, etc.) to JPEG using Pillow
    try:
        img = Image.open(io.BytesIO(raw_bytes))
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=85)
        raw_bytes = buf.getvalue()
    except Exception as e:
        return jsonify({"data": None, "error": f"Could not read image: {e}"}), 400

    image_data = base64.standard_b64encode(raw_bytes).decode("utf-8")

    try:
        client = _get_client()
        response = client.chat.completions.create(
            model="gpt-4o",
            max_tokens=1024,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{image_data}",
                                "detail": "high",
                            },
                        },
                        {"type": "text", "text": USER_PROMPT},
                    ],
                }
            ],
        )

        raw = response.choices[0].message.content.strip()
        # Strip markdown code fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        result = json.loads(raw)
        return jsonify({"data": result, "error": None})

    except json.JSONDecodeError as e:
        return jsonify({"data": None, "error": f"Failed to parse GPT-4o response: {e}"}), 500
    except Exception as e:
        return jsonify({"data": None, "error": f"OpenAI API error: {e}"}), 502
