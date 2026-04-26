"""
POST /api/estimate-dimensions
Uses GPT-4o Vision to detect all paintable surfaces in a room photo and
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

from openai import OpenAI
from flask import Blueprint, request, jsonify

estimate_dimensions_bp = Blueprint("estimate_dimensions", __name__)

_openai_client: OpenAI | None = None


def _get_client() -> OpenAI:
    global _openai_client
    if _openai_client is None:
        _openai_client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    return _openai_client


SYSTEM_PROMPT = """You are a professional paint estimator analyzing a room photo.

Detect every paintable surface. Return structured JSON that a paint calculator will use
to compute gallons for walls and trim separately.

MEASUREMENT RULES:
- Calibrate scale using reference objects: interior door = 80"H × 32"W, outlet plate = 4.5"H × 2.75"W,
  window sill = 36" above floor, kitchen counter = 36"H, standard ceiling = 8-9 ft.
- Label each wall A, B, C, D (visible ones only).
- Each wall is measured separately — never use total room square footage.
- Trim is measured as linear feet × width, NOT area.
- If the room is irregular, split walls into rectangles.
- Mark "estimated": true for any dimension you cannot measure precisely.
- Associate each opening with the wall it belongs to (wall_id field).

TRIM TYPES to detect separately if visible:
  baseboards, crown_molding, door_casings, window_casings

Return ONLY valid JSON:
{
  "walls": [
    {"id": "A", "label": "north wall", "width_ft": 14.0, "height_ft": 9.0, "estimated": false},
    {"id": "B", "label": "east wall",  "width_ft": 12.0, "height_ft": 9.0, "estimated": false}
  ],
  "trim": {
    "baseboards":     {"length_ft": 48.0, "width_in": 3.5,  "estimated": false},
    "crown_molding":  {"length_ft": 0.0,  "width_in": 4.0,  "estimated": true},
    "door_casings":   {"length_ft": 14.0, "width_in": 2.5,  "estimated": true},
    "window_casings": {"length_ft": 8.0,  "width_in": 2.5,  "estimated": true}
  },
  "openings": [
    {"id": "D1", "type": "door",   "wall_id": "A", "width_ft": 3.0, "height_ft": 6.8, "estimated": false},
    {"id": "W1", "type": "window", "wall_id": "B", "width_ft": 3.5, "height_ft": 4.0, "estimated": true}
  ],
  "ceiling_height_ft": 9.0,
  "confidence": "medium",
  "reference_used": "interior door on Wall A",
  "notes": "Crown molding not visible. Window dims estimated from proportion."
}

Rules:
- Omit trim types that are not visible (set length_ft: 0.0 and estimated: true if unsure).
- wall_id in openings must match a wall id in the walls array.
- confidence: "high" = reference object found, "medium" = proportion estimate, "low" = very uncertain."""


def _compute_totals(data: dict) -> dict:
    """Compute totals object from parsed GPT-4o output."""
    wall_area = sum(w.get("width_ft", 0) * w.get("height_ft", 0) for w in data.get("walls", []))
    openings_area = sum(o.get("width_ft", 0) * o.get("height_ft", 0) for o in data.get("openings", []))
    net_wall = max(0.0, wall_area - openings_area)

    trim = data.get("trim", {})
    trim_area = 0.0
    for t in trim.values():
        length = t.get("length_ft", 0)
        width_in = t.get("width_in", 0)
        trim_area += length * (width_in / 12.0)

    coverage = 400.0
    return {
        "wall_area_sqft": round(wall_area, 1),
        "openings_area_sqft": round(openings_area, 1),
        "net_wall_area_sqft": round(net_wall, 1),
        "trim_area_sqft": round(trim_area, 2),
        "paint_estimate": {
            "coverage_sqft_per_gallon": coverage,
            "wall_paint": {
                "1_coat_gallons": round(net_wall / coverage, 2),
                "2_coats_gallons": round(net_wall * 2 / coverage, 2),
            },
            "trim_paint": {
                "1_coat_gallons": round(trim_area / coverage, 2),
                "2_coats_gallons": round(trim_area * 2 / coverage, 2),
            },
        },
    }


_FALLBACK = {
    "walls": [
        {"id": "A", "label": "wall A", "width_ft": 14.0, "height_ft": 9.0, "estimated": True},
        {"id": "B", "label": "wall B", "width_ft": 14.0, "height_ft": 9.0, "estimated": True},
        {"id": "C", "label": "wall C", "width_ft": 12.0, "height_ft": 9.0, "estimated": True},
        {"id": "D", "label": "wall D", "width_ft": 12.0, "height_ft": 9.0, "estimated": True},
    ],
    "trim": {
        "baseboards":     {"length_ft": 52.0, "width_in": 3.5, "estimated": True},
        "crown_molding":  {"length_ft": 0.0,  "width_in": 4.0, "estimated": True},
        "door_casings":   {"length_ft": 14.0, "width_in": 2.5, "estimated": True},
        "window_casings": {"length_ft": 8.0,  "width_in": 2.5, "estimated": True},
    },
    "openings": [
        {"id": "D1", "type": "door",   "wall_id": "A", "width_ft": 3.0, "height_ft": 6.8, "estimated": True},
        {"id": "W1", "type": "window", "wall_id": "B", "width_ft": 3.5, "height_ft": 4.0, "estimated": True},
    ],
    "ceiling_height_ft": 9.0,
    "confidence": "low",
    "reference_used": "none",
    "notes": "Default estimate — image not analyzed",
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
                                "url": f"data:image/jpeg;base64,{image_b64}",
                                "detail": "high",
                            },
                        },
                        {"type": "text", "text": SYSTEM_PROMPT},
                    ],
                }
            ],
        )

        raw = response.choices[0].message.content.strip()
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
        result.setdefault("trim", {})
        result.setdefault("openings", [])
        result.setdefault("ceiling_height_ft", 9.0)
        result.setdefault("confidence", "medium")
        result.setdefault("reference_used", "")
        result.setdefault("notes", "")

        # Compute totals server-side
        result["totals"] = _compute_totals(result)

        return jsonify({"data": result})

    except Exception as e:
        fallback = dict(_FALLBACK)
        fallback["notes"] = f"Estimate only — detection error: {e}"
        return jsonify({"data": fallback})
