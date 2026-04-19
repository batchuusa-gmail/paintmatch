"""
POST /api/estimate-dimensions
Uses Claude Vision to detect all paintable surfaces in a room photo and
return structured wall/trim/opening data for accurate paint estimation.

Output schema:
  walls    — list of {label, width_ft, height_ft}
  trim     — list of {label, length_ft, width_in}
  openings — list of {label, width_ft, height_ft}
  ceiling_height_ft — float
  confidence — "high" | "medium" | "low"
  notes    — string (reference object used, caveats)
"""
import base64
import json
import os
import re

import anthropic
from flask import Blueprint, request, jsonify

estimate_dimensions_bp = Blueprint("estimate_dimensions", __name__)

_anthropic_client: anthropic.Anthropic | None = None


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


SYSTEM_PROMPT = """You are a professional paint estimator analyzing a room photo.

Detect every paintable surface and return structured measurements so a paint calculator
can compute gallons needed — separately for walls and trim.

MEASUREMENT RULES:
- Use any known reference object to calibrate scale: interior door (80"H × 32"W typical),
  standard outlet/switch plate (4.5"H × 2.75"W), window (varies), kitchen counter (36"H).
- Estimate each WALL separately — do not use total room square footage.
- TRIM is always measured as linear length × trim width, NOT area.
- OPENINGS (doors + windows) must be listed so they can be subtracted from wall area.
- If a dimension is unclear, estimate it and flag in "notes".

CALCULATION TO APPLY AFTER THIS PROMPT (do NOT compute — just provide the measurements):
  paintable_wall_sqft = sum(wall.width × wall.height) − sum(opening.width × opening.height)
  trim_sqft = sum(trim.length_ft × trim.width_in / 12)

Return ONLY valid JSON — no markdown, no extra text:
{
  "walls": [
    {"label": "wall 1", "width_ft": 14.0, "height_ft": 9.0},
    {"label": "wall 2", "width_ft": 12.0, "height_ft": 9.0}
  ],
  "trim": [
    {"label": "baseboards", "length_ft": 52.0, "width_in": 3.5},
    {"label": "door casings", "length_ft": 14.0, "width_in": 2.5},
    {"label": "window casings", "length_ft": 8.0, "width_in": 2.5}
  ],
  "openings": [
    {"label": "door", "width_ft": 3.0, "height_ft": 6.8},
    {"label": "window", "width_ft": 3.5, "height_ft": 4.0}
  ],
  "ceiling_height_ft": 9.0,
  "confidence": "medium",
  "notes": "Calibrated from interior door. Trim widths estimated at standard sizes."
}

Rules:
- Include all walls visible — even partial ones.
- Baseboards run the full room perimeter minus door openings.
- Crown molding (if visible) is separate trim entry.
- Door and window casings are separate trim entries.
- If ceiling will be painted, add it as a wall entry with label "ceiling".
- If a surface is not visible or not applicable, omit it from the list.
- confidence = "high" if a clear reference object was found, "medium" if estimated from
  proportions, "low" if very uncertain."""

_FALLBACK = {
    "walls": [
        {"label": "wall 1", "width_ft": 14.0, "height_ft": 9.0},
        {"label": "wall 2", "width_ft": 14.0, "height_ft": 9.0},
        {"label": "wall 3", "width_ft": 12.0, "height_ft": 9.0},
        {"label": "wall 4", "width_ft": 12.0, "height_ft": 9.0},
    ],
    "trim": [
        {"label": "baseboards", "length_ft": 52.0, "width_in": 3.5},
        {"label": "door casings", "length_ft": 14.0, "width_in": 2.5},
    ],
    "openings": [
        {"label": "door", "width_ft": 3.0, "height_ft": 6.8},
        {"label": "window", "width_ft": 3.5, "height_ft": 4.0},
    ],
    "ceiling_height_ft": 9.0,
    "confidence": "low",
    "notes": "Default estimate — no image provided",
}


@estimate_dimensions_bp.route("/api/estimate-dimensions", methods=["POST"])
def estimate_dimensions():
    try:
        data = request.get_json(force=True)
        image_b64 = data.get("image_b64", "")
        if not image_b64:
            return jsonify({"data": _FALLBACK})

        if "," in image_b64:
            image_b64 = image_b64.split(",", 1)[1]

        client = _get_client()
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
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
        if raw.startswith("```"):
            raw = re.sub(r"^```[a-z]*\n?", "", raw)
            raw = re.sub(r"\n?```$", "", raw).strip()

        json_match = re.search(r"\{.*\}", raw, re.DOTALL)
        if json_match:
            result = json.loads(json_match.group())
        else:
            result = json.loads(raw)

        # Ensure required keys exist
        result.setdefault("walls", _FALLBACK["walls"])
        result.setdefault("trim", [])
        result.setdefault("openings", [])
        result.setdefault("ceiling_height_ft", 9.0)
        result.setdefault("confidence", "medium")
        result.setdefault("notes", "")

        return jsonify({"data": result})

    except Exception as e:
        fallback = dict(_FALLBACK)
        fallback["notes"] = f"Estimate only — detection error: {e}"
        return jsonify({"data": fallback})
