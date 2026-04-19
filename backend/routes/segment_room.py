"""
POST /api/segment-room
Single-pass surface segmentation — optimised for speed and reliability.

Pipeline:
  1. Claude Vision: one call, identifies obstacles + seeds per surface (~5s).
  2. SAM2: parallel calls for all detected surfaces, max 3 seeds each, 25s hard timeout.
  3. Returns base64 PNG masks keyed by surface name.

Total latency: ~25-40s.
"""
import base64
import io
import json
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FutureTimeout

import anthropic
import numpy as np
from flask import Blueprint, jsonify, request
from PIL import Image, ImageOps

from routes.segment_wall import _sam_segment, _segment_auto, _clean

segment_room_bp = Blueprint("segment_room", __name__)

_anthropic_client = None


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


SEED_PROMPT = """Analyze this room photo and return seed coordinates for surface segmentation.

Step 1 — Map all obstacles: note every door, window, doorway opening, large furniture piece,
fireplace, or artwork. Record their approximate center (cx, cy) and size.

Step 2 — For each paintable surface, place 3 seed points in OBSTACLE-FREE zones.
A door splits a wall into two sections — place one seed LEFT of the door and one RIGHT.
Seeds must be on flat, unobstructed surface area (not furniture, not door panels, not trim).

Return ONLY valid JSON:
{
  "obstacles": [
    {"type": "door", "cx": 0.40, "cy": 0.55, "w": 0.15, "h": 0.50}
  ],
  "wall":    [[x1,y1], [x2,y2], [x3,y3]],
  "ceiling": [[x1,y1], [x2,y2]],
  "floor":   [[x1,y1], [x2,y2]],
  "trim":    [[x1,y1], [x2,y2]]
}

Placement rules:
- wall seeds: middle of each visible wall section, y between 0.25–0.75, stay 0.10+ away from any obstacle cx
- ceiling seeds: y ≤ 0.12, spread across x, away from light fixtures
- floor seeds: y ≥ 0.85, open floor area, not on rugs or near furniture
- trim seeds: y ≥ 0.88 (baseboard) OR immediately on a door/window frame strip; NEVER on furniture
- If a surface is not clearly visible, omit its key entirely
- trim: omit if no distinct baseboard/molding visible"""


# Coverage bounds: reject masks outside these ranges (prevents wrong-object selection)
_COVERAGE_BOUNDS = {
    "wall":    (0.04, 0.80),
    "ceiling": (0.04, 0.65),
    "floor":   (0.04, 0.65),
    "trim":    (0.003, 0.12),  # trim is thin; reject furniture-sized masks
}

_SAM_TIMEOUT_S = 25  # hard limit per surface


def _geometric_clip(mask: Image.Image, surface: str) -> Image.Image:
    """
    Hard-clip a SAM2 mask to the region where that surface can physically exist.
    This prevents wall seeds from capturing ceiling/floor and vice-versa.

    Fractions are of image height (y-axis):
      ceiling → keep only top 28%
      floor   → keep only bottom 30%  (y >= 70%)
      wall    → remove top 12% and bottom 12%
      trim    → keep only bottom 22%  (baseboards / door frames at floor level)
    """
    arr = np.array(mask).copy()
    h = arr.shape[0]

    if surface == "ceiling":
        arr[int(h * 0.28):, :] = 0
    elif surface == "floor":
        arr[:int(h * 0.70), :] = 0
    elif surface == "wall":
        arr[:int(h * 0.12), :] = 0   # remove ceiling band
        arr[int(h * 0.88):, :] = 0   # remove floor band
    elif surface == "trim":
        arr[:int(h * 0.78), :] = 0   # trim is near floor only

    return Image.fromarray(arr, "L")


def _segment_surface(pil: Image.Image, surface: str, seeds: list) -> tuple[str, str | None]:
    """
    Try up to 3 seeds with SAM2, apply geometric clip, pick best coverage.
    Never falls back to auto-segmentation for trim (would grab furniture/walls).
    """
    cov_min, cov_max = _COVERAGE_BOUNDS.get(surface, (0.04, 0.80))
    best_mask = None
    best_coverage = 0.0

    for seed in seeds[:3]:
        sx, sy = float(seed[0]), float(seed[1])
        try:
            raw = _sam_segment(pil, sx, sy)
            # Clip to geometric region before evaluating coverage
            clipped = _geometric_clip(raw, surface)
            arr = np.array(clipped)
            coverage = float((arr > 127).sum()) / arr.size
            print(f"[seg-room] {surface} seed {seed} → {coverage:.1%} after clip (ok={cov_min:.1%}-{cov_max:.1%})")

            if cov_min <= coverage <= cov_max and coverage > best_coverage:
                best_mask = clipped
                best_coverage = coverage
        except Exception as e:
            print(f"[seg-room] SAM {surface} {seed} failed: {e}")

    if best_mask is None:
        if surface == "trim":
            print(f"[seg-room] trim: no valid mask, skipping")
            return surface, None
        print(f"[seg-room] {surface}: no valid SAM mask, trying auto")
        try:
            best_mask = _geometric_clip(_segment_auto(pil, surface), surface)
        except Exception as e:
            print(f"[seg-room] {surface} auto failed: {e}")
            return surface, None

    try:
        cleaned = _clean(best_mask)
        buf = io.BytesIO()
        cleaned.save(buf, format="PNG")
        return surface, base64.b64encode(buf.getvalue()).decode()
    except Exception as e:
        print(f"[seg-room] {surface} encode failed: {e}")
        return surface, None


@segment_room_bp.route("/api/segment-room", methods=["POST"])
def segment_room():
    try:
        data = request.get_json(force=True, silent=True) or {}
        image_b64 = data.get("image_b64", "")

        if not image_b64:
            return jsonify({"error": "image_b64 required"}), 400

        if "," in image_b64:
            image_b64 = image_b64.split(",", 1)[1]

        try:
            image_bytes = base64.b64decode(image_b64)
            pil = Image.open(io.BytesIO(image_bytes))
            pil = ImageOps.exif_transpose(pil).convert("RGB")
        except Exception as e:
            return jsonify({"error": f"Image decode failed: {e}"}), 400

        # ── Claude Vision: obstacle map + seeds (single call) ─────────────────
        seeds_by_surface: dict = {}
        try:
            client = _get_client()
            response = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=600,
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {"type": "base64", "media_type": "image/jpeg", "data": image_b64},
                        },
                        {"type": "text", "text": SEED_PROMPT},
                    ],
                }],
            )
            raw = response.content[0].text.strip()
            raw = re.sub(r"^```[a-z]*\n?", "", raw)
            raw = re.sub(r"\n?```$", "", raw).strip()
            match = re.search(r"\{.*\}", raw, re.DOTALL)
            parsed = json.loads(match.group() if match else raw)

            # Extract surface seeds (everything except "obstacles")
            seeds_by_surface = {k: v for k, v in parsed.items() if k != "obstacles" and isinstance(v, list)}
            obstacles = parsed.get("obstacles", [])
            print(f"[seg-room] obstacles={len(obstacles)} surfaces={list(seeds_by_surface.keys())}")

        except Exception as e:
            print(f"[seg-room] Claude seed extraction failed: {e}")

        # Positional fallbacks for wall/ceiling/floor
        if not seeds_by_surface.get("wall"):
            seeds_by_surface["wall"] = [[0.25, 0.45], [0.75, 0.45], [0.50, 0.40]]
        if not seeds_by_surface.get("ceiling"):
            seeds_by_surface["ceiling"] = [[0.50, 0.06], [0.25, 0.06], [0.75, 0.06]]
        if not seeds_by_surface.get("floor"):
            seeds_by_surface["floor"] = [[0.50, 0.92], [0.25, 0.92], [0.75, 0.92]]

        # ── Parallel SAM2 with hard timeout ──────────────────────────────────
        masks: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {
                executor.submit(_segment_surface, pil, surface, seeds): surface
                for surface, seeds in seeds_by_surface.items()
            }
            # Collect results as they complete; skip any that exceed timeout
            for future in as_completed(futures, timeout=_SAM_TIMEOUT_S * len(futures)):
                try:
                    surface_name, mask_b64 = future.result(timeout=_SAM_TIMEOUT_S)
                    if mask_b64:
                        masks[surface_name] = mask_b64
                except (FutureTimeout, Exception) as e:
                    surface_name = futures[future]
                    print(f"[seg-room] {surface_name} timed out or errored: {e}")

        print(f"[seg-room] done. masks={list(masks.keys())}")
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
