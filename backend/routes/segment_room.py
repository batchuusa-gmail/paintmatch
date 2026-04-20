"""
POST /api/segment-room
AI-driven surface segmentation — Claude analyses each photo to find surfaces.

Pipeline:
  1. Claude Vision: analyses the specific photo, returns exact zone boundaries
     for ceiling/wall/floor/trim in that image + wall seed points.
  2. Ceiling + floor: color-zone mask within Claude-defined bounds (no SAM2).
  3. Wall: SAM2 with seed clipped to Claude-defined wall band.
  4. Trim: SAM2 clipped to Claude-defined trim band.

Claude determines the zones per-image — no hardcoded percentages.
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

_SAM_TIMEOUT_S = 30

_COVERAGE_BOUNDS = {
    "wall":    (0.04, 0.75),
    "ceiling": (0.02, 0.60),
    "floor":   (0.02, 0.60),
    "trim":    (0.001, 0.10),
}


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


ANALYSIS_PROMPT = """You are analysing a room photo for paint surface segmentation.

TASK: Identify the vertical position (top-to-bottom) of each paintable surface in this image.
Use structural cues — the ceiling/wall junction line, the wall/floor junction line, crown molding,
baseboards — NOT color, because wall and ceiling are often the same color.

Express each surface as [y_start, y_end] where 0.0 = very top of image, 1.0 = very bottom.

Return ONLY valid JSON:
{
  "zones": {
    "ceiling": [0.00, 0.18],
    "wall":    [0.18, 0.80],
    "floor":   [0.80, 1.00],
    "trim":    [0.84, 1.00]
  },
  "wall_seeds":  [[0.25, 0.50], [0.75, 0.50], [0.50, 0.48]],
  "trim_seeds":  [[0.30, 0.92], [0.70, 0.92]]
}

Zone identification rules:
- Find the ceiling/wall junction line — this is ceiling_end / wall_start
- Find the wall/floor junction line — this is wall_end / floor_start
- Look for: crown molding line, cornice line, shadow at ceiling join, floor/carpet edge
- Ceiling: from top (0.0) to the ceiling/wall junction
- Wall: from ceiling/wall junction to floor/wall junction (the large painted middle area)
- Floor: from floor/wall junction to bottom (1.0)
- Trim (baseboards): the last 3-8% before the floor; omit if not clearly visible
- Zones must NOT overlap: ceiling[1] == wall[0] and wall[1] == floor[0]

Special cases:
- High vaulted ceiling: ceiling zone may be 30-40% of image
- Camera aimed at wall (no ceiling visible): ceiling = [0.0, 0.04]
- Camera aimed at wall (no floor visible): floor = [0.96, 1.0]
- Stairs/balcony visible: treat the wall behind them as the wall zone

Seed rules:
- wall_seeds: place 2-3 seeds at y values in the MIDDLE of the wall zone (not near edges)
- Spread x values: 0.25, 0.50, 0.75
- Avoid furniture, doors, windows when choosing x positions
- trim_seeds: y at ~90-95% of image; omit key entirely if no clear baseboard"""


# ── Color-zone mask (ceiling / floor) ─────────────────────────────────────────

def _color_zone_mask(pil: Image.Image, y_start: float, y_end: float) -> Image.Image | None:
    """
    Build a mask using the dominant color found in the zone [y_start, y_end].
    Only pixels inside that zone are ever included — no bleed outside.
    """
    from skimage.color import rgb2lab

    w, h = pil.size
    scale = min(1.0, 512 / max(w, h))
    small = pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    arr   = np.array(small).astype(np.float32) / 255.0
    sh, sw = arr.shape[:2]

    r0 = int(sh * y_start)
    r1 = int(sh * y_end)
    if r1 <= r0:
        return None

    zone = arr[r0:r1, :, :]  # H×W×3 strip

    # Quantize to 32 levels per channel — find dominant color bin
    zone_u8   = (zone * 255).astype(np.uint8)
    zone_flat = zone_u8.reshape(-1, 3)
    q         = (zone_flat // 8).astype(np.int32)   # 32 levels per channel
    keys      = q[:, 0] * 1024 + q[:, 1] * 32 + q[:, 2]
    dom_key   = int(np.bincount(keys).argmax())

    dom_r = (((dom_key // 1024)) * 8 + 4) / 255.0
    dom_g = (((dom_key % 1024) // 32) * 8 + 4) / 255.0
    dom_b = (((dom_key % 32)) * 8 + 4) / 255.0
    dom_lab = rgb2lab(np.array([[[dom_r, dom_g, dom_b]]],
                               dtype=np.float64)).reshape(3)

    # Score every pixel in the zone against dominant color
    zone_lab = rgb2lab(zone.astype(np.float64)).reshape(-1, 3)
    diffs    = np.linalg.norm(zone_lab - dom_lab, axis=1)
    match    = (diffs < 22).reshape(r1 - r0, sw)

    out = np.zeros((sh, sw), dtype=np.uint8)
    out[r0:r1, :] = (match * 255).astype(np.uint8)

    # If color-match gives too little (< 30% of zone), fill whole zone solid
    if match.mean() < 0.30:
        out[r0:r1, :] = 255

    return Image.fromarray(out, "L").resize(pil.size, Image.NEAREST)


# ── Zone clip ─────────────────────────────────────────────────────────────────

def _zone_clip(arr: np.ndarray, y_start: float, y_end: float) -> np.ndarray:
    """Zero out everything outside [y_start, y_end] fraction of image height."""
    h   = arr.shape[0]
    out = arr.copy()
    out[:int(h * y_start), :] = 0
    out[int(h * y_end):, :]   = 0
    return out


# ── Per-surface segmentation ───────────────────────────────────────────────────

def _segment_surface(
    pil: Image.Image,
    surface: str,
    seeds: list,
    zone: tuple[float, float],
) -> tuple[str, str | None]:
    """
    Segment one surface using Claude-provided zone boundaries.
    Ceiling/floor: color-zone geometry.
    Wall/trim: SAM2 clipped to zone.
    """
    y0, y1 = zone
    cov_min, cov_max = _COVERAGE_BOUNDS.get(surface, (0.04, 0.75))

    # ── Ceiling / Floor: no SAM2 ─────────────────────────────────────────────
    if surface in ("ceiling", "floor"):
        print(f"[seg-room] {surface}: color-zone y={y0:.2f}–{y1:.2f}")
        try:
            mask = _color_zone_mask(pil, y0, y1)
            if mask is None:
                return surface, None
            arr      = np.array(mask)
            coverage = float((arr > 127).sum()) / arr.size
            print(f"[seg-room] {surface} coverage={coverage:.1%}")
            cleaned  = _clean(mask)
            buf      = io.BytesIO()
            cleaned.save(buf, format="PNG")
            return surface, base64.b64encode(buf.getvalue()).decode()
        except Exception as e:
            print(f"[seg-room] {surface} failed: {e}")
            return surface, None

    # ── Wall / Trim: SAM2 + zone clip ────────────────────────────────────────
    best_mask     = None
    best_coverage = 0.0

    for seed in seeds[:3]:
        sx, sy = float(seed[0]), float(seed[1])
        # Clamp seed into the zone with 5% margin from edges
        margin = (y1 - y0) * 0.10
        sy = max(y0 + margin, min(y1 - margin, sy))

        try:
            raw      = _sam_segment(pil, sx, sy)
            arr      = _zone_clip(np.array(raw), y0, y1)
            coverage = float((arr > 127).sum()) / arr.size
            print(f"[seg-room] {surface} seed ({sx:.2f},{sy:.2f}) → {coverage:.1%} in zone {y0:.2f}–{y1:.2f}")

            if cov_min <= coverage <= cov_max and coverage > best_coverage:
                best_mask     = Image.fromarray(arr, "L")
                best_coverage = coverage
        except Exception as e:
            print(f"[seg-room] {surface} SAM failed seed {seed}: {e}")

    if best_mask is None:
        if surface == "trim":
            print(f"[seg-room] trim: no valid SAM mask, skipping")
            return surface, None
        print(f"[seg-room] {surface}: SAM failed, geometric fallback in zone")
        try:
            raw  = _segment_auto(pil, surface)
            arr  = _zone_clip(np.array(raw), y0, y1)
            best_mask = Image.fromarray(arr, "L")
        except Exception as e:
            print(f"[seg-room] {surface} geometric fallback failed: {e}")
            return surface, None

    try:
        cleaned = _clean(best_mask)
        buf     = io.BytesIO()
        cleaned.save(buf, format="PNG")
        return surface, base64.b64encode(buf.getvalue()).decode()
    except Exception as e:
        print(f"[seg-room] {surface} encode failed: {e}")
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
            # Re-encode the rotation-corrected image — Claude must see the same
            # orientation that SAM2 will segment (critical for rotated phone photos)
            corrected_buf = io.BytesIO()
            pil.save(corrected_buf, format="JPEG", quality=90)
            corrected_b64 = base64.b64encode(corrected_buf.getvalue()).decode()
        except Exception as e:
            return jsonify({"error": f"Image decode failed: {e}"}), 400

        # ── Step 1: Claude analyses this specific photo ───────────────────────
        zones        = {}
        seeds_wall   = [[0.25, 0.50], [0.75, 0.50], [0.50, 0.45]]
        seeds_trim   = []

        try:
            client   = _get_client()
            response = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=600,
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": corrected_b64,  # rotation-corrected
                            },
                        },
                        {"type": "text", "text": ANALYSIS_PROMPT},
                    ],
                }],
            )
            raw    = response.content[0].text.strip()
            raw    = re.sub(r"^```[a-z]*\n?", "", raw)
            raw    = re.sub(r"\n?```$", "", raw).strip()
            match  = re.search(r"\{.*\}", raw, re.DOTALL)
            parsed = json.loads(match.group() if match else raw)

            zones      = parsed.get("zones", {})
            seeds_wall = parsed.get("wall_seeds", seeds_wall)
            seeds_trim = parsed.get("trim_seeds", [])

            print(f"[seg-room] Claude zones: {zones}")
            print(f"[seg-room] wall_seeds={len(seeds_wall)} trim_seeds={len(seeds_trim)}")

        except Exception as e:
            print(f"[seg-room] Claude analysis failed: {e}")

        # ── Fallback zones if Claude failed ───────────────────────────────────
        if not zones.get("ceiling"):
            zones["ceiling"] = [0.00, 0.20]
        if not zones.get("wall"):
            zones["wall"]    = [0.20, 0.80]
        if not zones.get("floor"):
            zones["floor"]   = [0.80, 1.00]

        # Enforce non-overlapping: wall starts where ceiling ends, floor starts where wall ends
        ceiling_end = zones["ceiling"][1]
        floor_start = zones["floor"][0]
        zones["wall"][0] = ceiling_end
        zones["wall"][1] = floor_start

        # ── Step 2: parallel segmentation per surface ─────────────────────────
        tasks = {
            "ceiling": ([], tuple(zones["ceiling"])),
            "wall":    (seeds_wall, tuple(zones["wall"])),
            "floor":   ([], tuple(zones["floor"])),
        }
        if seeds_trim and zones.get("trim"):
            tasks["trim"] = (seeds_trim, tuple(zones["trim"]))

        masks: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {
                executor.submit(_segment_surface, pil, surface, seeds, zone): surface
                for surface, (seeds, zone) in tasks.items()
            }
            for future in as_completed(futures, timeout=_SAM_TIMEOUT_S * 2 + 15):
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
                "zones":             zones,
            },
            "error": None,
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
