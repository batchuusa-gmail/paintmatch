"""
POST /api/segment-room
Auto-segments ALL paintable surfaces in a room image (wall, ceiling, floor, trim).

Pipeline:
  1. Claude Vision identifies 2-3 seed coordinates per surface in one API call.
  2. SAM 2 runs in parallel for each detected surface (wall/ceiling/floor/trim).
  3. Each surface uses the best seed; falls back to position-based SLIC if SAM fails.
  4. Returns base64 PNG masks keyed by surface name.

Total latency: ~20-30s (Claude Vision ~5s + parallel SAM2 ~15-20s).
"""
import base64
import io
import json
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

import anthropic
import numpy as np
from flask import Blueprint, jsonify, request
from PIL import Image, ImageOps

# Reuse helpers from segment_wall — _sam_segment, _segment_auto, _clean
from routes.segment_wall import _sam_segment, _segment_auto, _clean

segment_room_bp = Blueprint("segment_room", __name__)

_anthropic_client = None


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


SEED_PROMPT = """You are analyzing a room photo to identify paintable architectural surfaces.

For each visible surface, provide 2-3 seed points as [x, y] fractional coordinates
(0.0 = left/top edge, 1.0 = right/bottom edge).

CRITICAL RULES:
- Seeds must land on a FIXED ARCHITECTURAL surface — never on furniture, decor, appliances, or objects
- For each seed, mentally verify: "Is this pixel attached to the building structure, not a movable object?"
- Spread seeds across the surface — do not cluster them
- Avoid shadows, light sources, windows, mirrors, and transition zones between surfaces

TRIM RULES (most important — trim is easily confused with furniture):
- Trim = baseboards at the very bottom of walls, door frames around doorways, window moldings
- Baseboard seeds: place them at the very bottom edge of the wall where it meets the floor (y ≈ 0.85-0.97)
- Door frame seeds: place on the vertical or horizontal strip immediately bordering a door opening
- NEVER place a trim seed on furniture legs, coffee tables, shelves, or any freestanding object
- If trim is not clearly visible as architectural molding, OMIT the "trim" key entirely

Return ONLY valid JSON, no extra text:
{
  "wall": [[x1,y1], [x2,y2], [x3,y3]],
  "ceiling": [[x1,y1], [x2,y2]],
  "floor": [[x1,y1], [x2,y2]],
  "trim": [[x1,y1], [x2,y2]]
}

Surface definitions:
- wall: large flat vertical painted surfaces (exclude window glass, door panels, trim strips)
- ceiling: overhead horizontal surface
- floor: ground surface (hardwood, carpet, tile) — avoid rugs
- trim: ONLY fixed architectural moldings — baseboards, door frames, window casings, crown molding

Omit any key if that surface is not clearly visible. Only include points with >95% confidence."""


# Coverage bounds per surface — prevents SAM picking the wrong object
_COVERAGE_BOUNDS = {
    "wall":    (0.05, 0.75),   # walls are large
    "ceiling": (0.05, 0.60),   # ceiling is large
    "floor":   (0.05, 0.60),   # floor is large
    "trim":    (0.003, 0.12),  # trim is THIN — reject anything bigger (furniture, walls)
}


def _segment_surface(pil: Image.Image, surface: str, seeds: list) -> tuple[str, str | None]:
    """
    Run SAM2 for one surface using Claude-provided seed points.
    Tries each seed point, picks the mask whose coverage best matches the
    expected range for that surface type (thin for trim, large for walls).
    Falls back to position-based auto-segmentation only for non-trim surfaces.
    Returns (surface_name, mask_base64_png | None).
    """
    cov_min, cov_max = _COVERAGE_BOUNDS.get(surface, (0.03, 0.80))

    try:
        best_mask = None
        best_coverage = 0.0

        for seed in seeds[:3]:  # try up to 3 seeds
            sx, sy = float(seed[0]), float(seed[1])
            try:
                raw = _sam_segment(pil, sx, sy)
                arr = np.array(raw)
                coverage = float((arr > 127).sum()) / arr.size
                print(f"[segment-room] {surface} seed {seed} → coverage={coverage:.2%} (bounds {cov_min:.1%}-{cov_max:.1%})")
                # Accept only masks within the expected coverage range for this surface
                if cov_min <= coverage <= cov_max and coverage > best_coverage:
                    best_mask = raw
                    best_coverage = coverage
                elif coverage > cov_max:
                    print(f"[segment-room] {surface} seed {seed} rejected — too large ({coverage:.1%} > {cov_max:.1%}), likely wrong object")
            except Exception as e:
                print(f"[segment-room] SAM seed {seed} for {surface} failed: {e}")
                continue

        # Trim: never fall back to auto-segmentation (it would grab walls/furniture)
        if best_mask is None and surface == "trim":
            print(f"[segment-room] trim: no valid seed found, skipping (not returning bad mask)")
            return surface, None

        if best_mask is None:
            print(f"[segment-room] SAM found nothing for {surface}, using auto fallback")
            best_mask = _segment_auto(pil, surface)

        cleaned = _clean(best_mask)
        buf = io.BytesIO()
        cleaned.save(buf, format="PNG")
        mask_b64 = base64.b64encode(buf.getvalue()).decode()

        arr = np.array(cleaned)
        coverage = float((arr > 127).sum()) / arr.size
        print(f"[segment-room] {surface}: coverage={coverage:.2%}")
        return surface, mask_b64

    except Exception as e:
        print(f"[segment-room] {surface} completely failed: {e}")
        # Last-resort: try auto fallback
        try:
            raw = _segment_auto(pil, surface)
            cleaned = _clean(raw)
            buf = io.BytesIO()
            cleaned.save(buf, format="PNG")
            return surface, base64.b64encode(buf.getvalue()).decode()
        except Exception as e2:
            print(f"[segment-room] {surface} auto fallback also failed: {e2}")
            return surface, None


@segment_room_bp.route("/api/segment-room", methods=["POST"])
def segment_room():
    try:
        data = request.get_json(force=True, silent=True) or {}
        image_b64 = data.get("image_b64", "")

        if not image_b64:
            return jsonify({"error": "image_b64 required"}), 400

        # Strip data-URI prefix if present
        if "," in image_b64:
            image_b64 = image_b64.split(",", 1)[1]

        # Decode image
        try:
            image_bytes = base64.b64decode(image_b64)
            pil = Image.open(io.BytesIO(image_bytes))
            pil = ImageOps.exif_transpose(pil).convert("RGB")
        except Exception as e:
            return jsonify({"error": f"Image decode failed: {e}"}), 400

        # ── Step 1: Claude Vision → seed coordinates for each surface ──────────
        seeds_by_surface: dict = {}
        try:
            client = _get_client()
            response = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=512,
                messages=[{
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
                        {"type": "text", "text": SEED_PROMPT},
                    ],
                }],
            )

            raw_text = response.content[0].text.strip()
            # Strip markdown fences
            if raw_text.startswith("```"):
                raw_text = raw_text.split("```")[1]
                if raw_text.startswith("json"):
                    raw_text = raw_text[4:]
                raw_text = raw_text.strip()

            # Extract JSON object
            json_match = re.search(r"\{.*\}", raw_text, re.DOTALL)
            if json_match:
                seeds_by_surface = json.loads(json_match.group())
            print(f"[segment-room] Claude seeds: {seeds_by_surface}")

        except Exception as e:
            print(f"[segment-room] Claude seed extraction failed: {e}")
            # Position-based defaults — wall centre, ceiling top, floor bottom
            seeds_by_surface = {
                "wall":    [[0.50, 0.50], [0.25, 0.50]],
                "ceiling": [[0.50, 0.08], [0.75, 0.08]],
                "floor":   [[0.50, 0.90], [0.75, 0.90]],
            }

        # Ensure at least wall/ceiling/floor are present
        if not seeds_by_surface.get("wall"):
            seeds_by_surface["wall"] = [[0.50, 0.50], [0.25, 0.50]]
        if not seeds_by_surface.get("ceiling"):
            seeds_by_surface["ceiling"] = [[0.50, 0.08]]
        if not seeds_by_surface.get("floor"):
            seeds_by_surface["floor"] = [[0.50, 0.90]]

        # ── Step 2: Parallel SAM2 for all surfaces ──────────────────────────────
        masks: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {
                executor.submit(
                    _segment_surface, pil, surface, seeds
                ): surface
                for surface, seeds in seeds_by_surface.items()
            }
            for future in as_completed(futures):
                surface_name, mask_b64 = future.result()
                if mask_b64:
                    masks[surface_name] = mask_b64

        return jsonify({
            "data": {
                "masks": masks,
                "detected_surfaces": list(masks.keys()),
                "seeds": seeds_by_surface,
            },
            "error": None,
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
