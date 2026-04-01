"""
PM-9: Delta-E CIE2000 color matching utility.
Converts HEX ↔ LAB and computes perceptual color distance.
"""
from __future__ import annotations

import math
import re
from typing import Any

from colormath.color_objects import sRGBColor, LabColor
from colormath.color_conversions import convert_color
from colormath.color_diff import delta_e_cie2000


def hex_to_lab(hex_color: str) -> LabColor:
    """Convert a #RRGGBB hex string to CIE LAB color."""
    hex_color = hex_color.lstrip("#")
    r, g, b = (int(hex_color[i:i+2], 16) / 255.0 for i in (0, 2, 4))
    rgb = sRGBColor(r, g, b, is_upscaled=False)
    return convert_color(rgb, LabColor)


def compute_delta_e(hex1: str, hex2: str) -> float:
    """Return Delta-E CIE2000 distance between two hex colors. Lower = more similar."""
    lab1 = hex_to_lab(hex1)
    lab2 = hex_to_lab(hex2)
    return float(delta_e_cie2000(lab1, lab2))


def find_closest_colors(
    target_hex: str,
    color_rows: list[dict[str, Any]],
    top_n: int = 3,
    vendor: str | None = None,
) -> list[dict[str, Any]]:
    """
    Given a target hex and a list of paint_color dicts from Supabase,
    return the top_n closest matches sorted by Delta-E (ascending).

    Each result dict includes the original fields plus a 'delta_e' key.
    Optionally filter by vendor.
    """
    candidates = color_rows
    if vendor:
        candidates = [c for c in color_rows if c.get("vendor") == vendor]

    scored: list[tuple[float, dict]] = []
    for row in candidates:
        try:
            de = compute_delta_e(target_hex, row["hex"])
            scored.append((de, {**row, "delta_e": round(de, 4)}))
        except Exception:
            continue

    scored.sort(key=lambda x: x[0])
    return [item for _, item in scored[:top_n]]


def group_by_vendor(
    target_hex: str,
    color_rows: list[dict[str, Any]],
    top_n: int = 3,
) -> dict[str, list[dict[str, Any]]]:
    """
    Return top_n closest colors per vendor for the given target hex.
    Returns dict keyed by vendor name.
    """
    vendors = {"sherwin_williams", "benjamin_moore", "behr", "ppg", "valspar"}
    result: dict[str, list] = {}
    for v in vendors:
        result[v] = find_closest_colors(target_hex, color_rows, top_n=top_n, vendor=v)
    return result


def is_valid_hex(hex_color: str) -> bool:
    return bool(re.fullmatch(r"#[0-9A-Fa-f]{6}", hex_color))
