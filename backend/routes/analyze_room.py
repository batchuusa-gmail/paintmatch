"""
PM-10: POST /analyze-room
Accepts a room image, sends to Claude vision, returns structured palette JSON.
"""
import base64
import os
import json

import anthropic
from flask import Blueprint, request, jsonify

analyze_room_bp = Blueprint("analyze_room", __name__)

_anthropic_client: anthropic.Anthropic | None = None


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


SYSTEM_PROMPT = """You are an expert interior design color consultant.
Analyze the provided room photo and return ONLY valid JSON (no markdown, no extra text).
"""

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

    mime_type = image_file.content_type or "image/jpeg"
    if mime_type not in {"image/jpeg", "image/png", "image/webp", "image/gif"}:
        return jsonify({"data": None, "error": f"Unsupported image type: {mime_type}"}), 400

    image_data = base64.standard_b64encode(image_file.read()).decode("utf-8")

    try:
        client = _get_client()
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": mime_type,
                                "data": image_data,
                            },
                        },
                        {"type": "text", "text": USER_PROMPT},
                    ],
                }
            ],
        )

        raw = message.content[0].text.strip()
        # Strip markdown code fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        result = json.loads(raw)
        return jsonify({"data": result, "error": None})

    except json.JSONDecodeError as e:
        return jsonify({"data": None, "error": f"Failed to parse Claude response: {e}"}), 500
    except anthropic.APIError as e:
        return jsonify({"data": None, "error": f"Anthropic API error: {e}"}), 502
    except Exception as e:
        return jsonify({"data": None, "error": str(e)}), 500
