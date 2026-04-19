"""
PM-48: POST /api/estimate-dimensions
Accepts a room image (base64), uses Claude Vision to detect reference objects
and estimate wall dimensions.
"""
import base64
import os
import json

import anthropic
from flask import Blueprint, request, jsonify

estimate_dimensions_bp = Blueprint("estimate_dimensions", __name__)

_anthropic_client: anthropic.Anthropic | None = None


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


SYSTEM_PROMPT = (
    "You are a room measurement assistant. Analyze this room photo and identify any known "
    "reference objects (interior door, window, light switch plate, electrical outlet, kitchen counter). "
    "For the best reference object you can find, return ONLY valid JSON: "
    '{ "reference_object": str, "reference_width_inches": float, "reference_height_inches": float, '
    '"pixel_width": int, "pixel_height": int, "pixels_per_inch": float, '
    '"estimated_wall_width_ft": float, "estimated_room_depth_ft": float, '
    '"confidence": "high"|"medium"|"low", "reason": str }. '
    "If no reference found, set confidence to 'low' and estimate from room proportions only."
)

_FALLBACK = {
    "confidence": "low",
    "estimated_wall_width_ft": 12.0,
    "estimated_room_depth_ft": 12.0,
    "reference_object": "none",
    "reason": "no reference detected",
}


@estimate_dimensions_bp.route("/api/estimate-dimensions", methods=["POST"])
def estimate_dimensions():
    try:
        data = request.get_json(force=True)
        image_b64 = data.get("image_b64", "")
        if not image_b64:
            return jsonify({"data": _FALLBACK})

        # Strip data-URI prefix if present
        if "," in image_b64:
            image_b64 = image_b64.split(",", 1)[1]

        client = _get_client()
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=512,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": image_b64,
                            },
                        },
                        {"type": "text", "text": SYSTEM_PROMPT},
                    ],
                }
            ],
        )

        raw = response.content[0].text.strip()
        # Strip markdown code fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
            raw = raw.strip()

        result = json.loads(raw)
        return jsonify({"data": result})

    except Exception as e:
        fallback = dict(_FALLBACK)
        fallback["reason"] = str(e)
        return jsonify({"data": fallback})
