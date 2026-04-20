"""
POST /api/segment-room
Room surface segmentation — hard exclusive zones, no surface bleeding.

Zone boundaries (% of image height):
  ceiling → 0% – 22%    (hard ceiling, never overlaps wall)
  wall    → 22% – 80%   (SAM2 result clipped to this band)
  floor   → 80% – 100%  (hard floor, never overlaps wall)
  trim    → 76% – 100%  (baseboard strip, slight overlap with floor ok)

Ceiling + floor use pure color-zone geometry (no SAM2 = fast + reliable).
Wall uses SAM2 auto-seg clipped to the wall band (22–80%).
Trim uses SAM2 clipped to bottom 24%.

Total latency: ~15-20s (ceiling/floor instant, 1-2 SAM2 calls for wall/trim).
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

# Hard zone boundaries (fraction of image height)
_ZONE = {
    "ceiling": (0.00, 0.22),   # top 22%
    "wall":    (0.22, 0.80),   # middle 58%
    "floor":   (0.80, 1.00),   # bottom 20%
    "trim":    (0.76, 1.00),   # bottom 24% (baseboards)
}

_COVERAGE_BOUNDS = {
    "wall":    (0.04, 0.70),
    "ceiling": (0.02, 0.50),
    "floor":   (0.02, 0.50),
    "trim":    (0.002, 0.08),
}

_SAM_TIMEOUT_S = 30


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


SEED_PROMPT = """Analyze this room photo and return seed coordinates for wall and trim segmentation.

Map obstacles (doors, windows, furniture) first, then place seeds for wall only.

Return ONLY valid JSON:
{
  "obstacles": [{"type": "door", "cx": 0.40, "cy": 0.55}],
  "wall": [[x1,y1], [x2,y2], [x3,y3]],
  "trim": [[x1,y1], [x2,y2]]
}

Rules:
- wall seeds: y between 0.30 and 0.70 (middle of wall, NOT near ceiling or floor)
- Stay 0.12 away from door/window center x
- trim: y >= 0.88 on baseboard only; omit key entirely if no clear trim
- NO ceiling or floor seeds — those are handled separately"""


# ── Hard zone clip ─────────────────────────────────────────────────────────────

def _zone_clip(arr: np.ndarray, surface: str) -> np.ndarray:
    """Zero out everything outside this surface's exclusive zone."""
    h = arr.shape[0]
    y0, y1 = _ZONE[surface]
    out = arr.copy()
    out[:int(h * y0), :] = 0
    out[int(h * y1):, :] = 0
    return out


# ── Ceiling / floor: color-zone geometry (no SAM2) ────────────────────────────

def _color_zone_mask(pil: Image.Image, surface: str) -> Image.Image | None:
    """
    Build a mask using only pixels inside the exclusive zone that match
    the dominant color found in that zone.

    ceiling → top 22%, dominant bright color
    floor   → bottom 20%, dominant dark/neutral color

    No pixels outside the zone are ever included.
    """
    from skimage.color import rgb2lab

    # Work at 512px for speed
    w, h = pil.size
    scale = 512 / max(w, h)
    small = pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    arr   = np.array(small).astype(np.float32) / 255.0  # H×W×3, float 0-1
    sh, sw = arr.shape[:2]

    y0, y1 = _ZONE[surface]
    r0, r1 = int(sh * y0), int(sh * y1)
    zone   = arr[r0:r1, :, :]  # the exclusive zone strip

    if zone.size == 0:
        return None

    # Find the single most-common pixel color in the zone
    # Use 8-bit quantized colors for histogram
    zone_u8 = (zone * 255).astype(np.uint8)
    zone_flat = zone_u8.reshape(-1, 3)
    # Quantize to 16 levels per channel to group similar colors
    q = (zone_flat // 16).astype(np.int32)
    keys = q[:, 0] * 256 + q[:, 1] * 16 + q[:, 2]
    dominant_key = int(np.bincount(keys).argmax())
    dom_r = ((dominant_key // 256) * 16 + 8) / 255.0
    dom_g = (((dominant_key % 256) // 16) * 16 + 8) / 255.0
    dom_b = ((dominant_key % 16) * 16 + 8) / 255.0
    dom_lab = rgb2lab(np.array([[[dom_r, dom_g, dom_b]]]).astype(np.float64)).reshape(3)

    # Mark all pixels in the zone with similar LAB color
    zone_lab = rgb2lab(zone.astype(np.float64)).reshape(-1, 3)
    diffs    = np.linalg.norm(zone_lab - dom_lab, axis=1)
    match    = (diffs < 20).reshape(r1 - r0, sw)

    out = np.zeros((sh, sw), dtype=np.uint8)
    out[r0:r1, :] = (match * 255).astype(np.uint8)

    return Image.fromarray(out, "L").resize(pil.size, Image.NEAREST)


# ── Per-surface segmentation ───────────────────────────────────────────────────

def _segment_surface(pil: Image.Image, surface: str, seeds: list) -> tuple[str, str | None]:
    cov_min, cov_max = _COVERAGE_BOUNDS.get(surface, (0.04, 0.70))

    # ── Ceiling / Floor: color-zone only, zero SAM2 ──────────────────────────
    if surface in ("ceiling", "floor"):
        print(f"[seg-room] {surface}: color-zone (no SAM2)")
        try:
            mask = _color_zone_mask(pil, surface)
            if mask is None:
                return surface, None
            arr      = np.array(mask)
            coverage = float((arr > 127).sum()) / arr.size
            print(f"[seg-room] {surface} coverage={coverage:.1%}")
            if coverage < cov_min:
                # Fallback: fill the entire zone solid
                h, w = arr.shape
                y0, y1 = _ZONE[surface]
                arr[:] = 0
                arr[int(h * y0):int(h * y1), :] = 255
                mask = Image.fromarray(arr, "L")
                coverage = float((arr > 127).sum()) / arr.size
                print(f"[seg-room] {surface} fallback solid zone coverage={coverage:.1%}")
            cleaned = _clean(mask)
            buf = io.BytesIO()
            cleaned.save(buf, format="PNG")
            return surface, base64.b64encode(buf.getvalue()).decode()
        except Exception as e:
            print(f"[seg-room] {surface} color-zone failed: {e}")
            return surface, None

    # ── Wall: SAM2 → hard-clip to wall zone (22%–80%) ────────────────────────
    if surface == "wall":
        best_mask     = None
        best_coverage = 0.0

        for seed in seeds[:3]:
            sx, sy = float(seed[0]), float(seed[1])
            # Force seed y into wall zone (never in ceiling/floor band)
            sy = max(0.28, min(0.72, sy))
            try:
                raw = _sam_segment(pil, sx, sy)
                # Hard clip: wall cannot go above 22% or below 80%
                arr     = np.array(raw)
                arr     = _zone_clip(arr, "wall")
                clipped = Image.fromarray(arr, "L")
                coverage = float((arr > 127).sum()) / arr.size
                print(f"[seg-room] wall seed ({sx:.2f},{sy:.2f}) → {coverage:.1%} after zone clip")
                if cov_min <= coverage <= cov_max and coverage > best_coverage:
                    best_mask     = clipped
                    best_coverage = coverage
            except Exception as e:
                print(f"[seg-room] wall SAM failed seed {seed}: {e}")

        if best_mask is None:
            print(f"[seg-room] wall: SAM failed, geometric fallback")
            try:
                raw  = _segment_auto(pil, "wall")
                arr  = _zone_clip(np.array(raw), "wall")
                best_mask = Image.fromarray(arr, "L")
            except Exception as e:
                print(f"[seg-room] wall geometric fallback failed: {e}")
                return surface, None

        try:
            cleaned = _clean(best_mask)
            buf = io.BytesIO()
            cleaned.save(buf, format="PNG")
            return surface, base64.b64encode(buf.getvalue()).decode()
        except Exception as e:
            print(f"[seg-room] wall encode failed: {e}")
            return surface, None

    # ── Trim: SAM2 → hard-clip to trim zone (76%–100%) ───────────────────────
    if surface == "trim":
        best_mask     = None
        best_coverage = 0.0

        for seed in seeds[:3]:
            sx, sy = float(seed[0]), float(seed[1])
            sy = max(0.80, min(0.96, sy))   # force into trim zone
            try:
                raw      = _sam_segment(pil, sx, sy)
                arr      = _zone_clip(np.array(raw), "trim")
                clipped  = Image.fromarray(arr, "L")
                coverage = float((arr > 127).sum()) / arr.size
                print(f"[seg-room] trim seed ({sx:.2f},{sy:.2f}) → {coverage:.1%}")
                if cov_min <= coverage <= cov_max and coverage > best_coverage:
                    best_mask     = clipped
                    best_coverage = coverage
            except Exception as e:
                print(f"[seg-room] trim SAM failed seed {seed}: {e}")

        if best_mask is None:
            print(f"[seg-room] trim: no valid mask, skipping")
            return surface, None

        try:
            cleaned = _clean(best_mask)
            buf = io.BytesIO()
            cleaned.save(buf, format="PNG")
            return surface, base64.b64encode(buf.getvalue()).decode()
        except Exception as e:
            print(f"[seg-room] trim encode failed: {e}")
            return surface, None

    return surface, None


# ── Route ─────────────────────────────────────────────────────────────────────

@segment_room_bp.route("/api/segment-room", methods=["POST"])
def segment_room():
    try:
        data      = request.get_json(force=True, silent=True) or {}
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

        # ── Claude Vision: wall seeds only ────────────────────────────────────
        seeds_by_surface: dict = {}
        try:
            client   = _get_client()
            response = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=400,
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
            raw    = response.content[0].text.strip()
            raw    = re.sub(r"^```[a-z]*\n?", "", raw)
            raw    = re.sub(r"\n?```$", "", raw).strip()
            match  = re.search(r"\{.*\}", raw, re.DOTALL)
            parsed = json.loads(match.group() if match else raw)

            seeds_by_surface = {
                k: v for k, v in parsed.items()
                if k != "obstacles" and isinstance(v, list)
            }
            print(f"[seg-room] seeds={list(seeds_by_surface.keys())}")

        except Exception as e:
            print(f"[seg-room] Claude seed extraction failed: {e}")

        # Wall seeds fallback
        if not seeds_by_surface.get("wall"):
            seeds_by_surface["wall"] = [[0.25, 0.50], [0.75, 0.50], [0.50, 0.45]]

        # Ceiling and floor always go through color-zone (no seeds needed)
        seeds_by_surface["ceiling"] = []
        seeds_by_surface["floor"]   = []

        # ── Parallel: ceiling/floor finish instantly, wall/trim take ~20s ────
        masks: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {
                executor.submit(_segment_surface, pil, surface, seeds): surface
                for surface, seeds in seeds_by_surface.items()
            }
            for future in as_completed(futures, timeout=_SAM_TIMEOUT_S * 2 + 10):
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
                "masks":             masks,
                "detected_surfaces": list(masks.keys()),
                "seeds":             seeds_by_surface,
            },
            "error": None,
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
