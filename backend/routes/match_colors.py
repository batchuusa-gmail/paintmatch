"""
PM-12: POST /match-colors
Accepts a HEX color, returns top-N closest matches per vendor using Delta-E CIE2000.
"""
from typing import Optional
from flask import Blueprint, request, jsonify

from utils.color_utils import group_by_vendor, is_valid_hex
from utils.supabase_client import get_supabase

match_colors_bp = Blueprint("match_colors", __name__)

_color_cache: Optional[list] = None


def _load_all_colors() -> list:
    """Load all paint colors from Supabase into memory (cached after first call)."""
    global _color_cache
    if _color_cache is None:
        sb = get_supabase()
        response = (
            sb.table("paint_colors")
            .select(
                "id,vendor,color_name,color_code,hex,lrv,"
                "finish_options,price_per_gallon,coverage_sqft"
            )
            .execute()
        )
        _color_cache = response.data or []
    return _color_cache


@match_colors_bp.route("/match-colors", methods=["POST"])
def match_colors():
    data = request.get_json(force=True, silent=True) or {}
    hex_color = data.get("hex", "").strip()
    top_n = int(data.get("top_n", 3))
    top_n = max(1, min(top_n, 10))  # clamp 1–10

    if not is_valid_hex(hex_color):
        return jsonify({"data": None, "error": "Invalid hex color. Expected #RRGGBB format."}), 400

    try:
        all_colors = _load_all_colors()

        if not all_colors:
            return jsonify({"data": None, "error": "Color database is empty. Run the seed script first."}), 503

        vendor_matches = group_by_vendor(hex_color, all_colors, top_n=top_n)

        # Flatten to array of rows grouped by vendor for easy Flutter consumption
        result = []
        for vendor, matches in vendor_matches.items():
            for m in matches:
                result.append({
                    "vendor": vendor,
                    "color_name": m.get("color_name"),
                    "color_code": m.get("color_code"),
                    "hex": m.get("hex"),
                    "lrv": m.get("lrv"),
                    "price_per_gallon": m.get("price_per_gallon"),
                    "coverage_sqft": m.get("coverage_sqft"),
                    "finish_options": m.get("finish_options", []),
                    "delta_e": m.get("delta_e"),
                })

        # Sort across vendors by delta_e so Flutter can highlight best match
        result.sort(key=lambda x: x["delta_e"])

        return jsonify({"data": result, "error": None})

    except Exception as e:
        return jsonify({"data": None, "error": str(e)}), 500


@match_colors_bp.route("/colors", methods=["GET"])
def list_colors():
    """Return all paint colors with optional vendor/search filtering."""
    vendor = request.args.get("vendor", "").strip().lower()
    search = request.args.get("search", "").strip().lower()
    limit = int(request.args.get("limit", 200))
    offset = int(request.args.get("offset", 0))

    try:
        all_colors = _load_all_colors()
        filtered = all_colors

        if vendor:
            filtered = [c for c in filtered if c.get("vendor", "").lower() == vendor]
        if search:
            filtered = [c for c in filtered
                        if search in c.get("color_name", "").lower()
                        or search in c.get("color_code", "").lower()]

        total = len(filtered)
        page = filtered[offset: offset + limit]

        result = [{
            "vendor": c.get("vendor"),
            "color_name": c.get("color_name"),
            "color_code": c.get("color_code"),
            "hex": c.get("hex"),
            "lrv": c.get("lrv"),
            "price_per_gallon": c.get("price_per_gallon"),
            "coverage_sqft": c.get("coverage_sqft"),
            "finish_options": c.get("finish_options", []),
        } for c in page]

        return jsonify({"data": result, "total": total, "error": None})

    except Exception as e:
        return jsonify({"data": None, "total": 0, "error": str(e)}), 500


@match_colors_bp.route("/match-colors/refresh-cache", methods=["POST"])
def refresh_cache():
    """Force-reload the in-memory color cache (call after seeding)."""
    global _color_cache
    _color_cache = None
    _load_all_colors()
    return jsonify({"data": {"count": len(_color_cache)}, "error": None})
