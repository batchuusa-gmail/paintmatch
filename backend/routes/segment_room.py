"""
POST /api/segment-room
Auto-segments ALL paintable surfaces in a room image.

Two-pass pipeline:
  Pass 1 — Scene analysis: Claude identifies shot type, obstacle locations
            (doors, windows, furniture), and safe zones per surface.
  Pass 2 — Seed placement: Claude places precise seeds using the obstacle map.
  Pass 3 — SAM2 runs in parallel for all surfaces using best seeds.

Two-pass approach handles wide shots and rooms with doors much better than
single-pass: obstacles are mapped first so seeds are never placed near them.

Total latency: ~25-35s (2x Claude ~8s + parallel SAM2 ~20s).
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

from routes.segment_wall import _sam_segment, _segment_auto, _clean

segment_room_bp = Blueprint("segment_room", __name__)

_anthropic_client = None


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


# ── Pass 1: Scene geometry analysis ──────────────────────────────────────────

SCENE_ANALYSIS_PROMPT = """Analyze this room photo and return a JSON scene map.

TASK: Identify obstacles and safe paintable zones. This will be used to place
segmentation seeds — seeds must land on a pure, unobstructed surface.

Return ONLY valid JSON, no extra text:
{
  "shot_type": "wide-angle" | "close-up" | "corner" | "single-wall",
  "obstacles": [
    {"type": "door" | "window" | "furniture" | "fireplace" | "artwork" | "light_fixture",
     "cx": 0.5, "cy": 0.5, "approx_width": 0.15, "approx_height": 0.4}
  ],
  "surfaces": {
    "wall": {
      "visible": true,
      "segments": [
        {"cx": 0.2, "cy": 0.5, "clear_radius": 0.08},
        {"cx": 0.75, "cy": 0.45, "clear_radius": 0.10}
      ]
    },
    "ceiling": {
      "visible": true,
      "segments": [{"cx": 0.5, "cy": 0.07, "clear_radius": 0.12}]
    },
    "floor": {
      "visible": true,
      "segments": [{"cx": 0.5, "cy": 0.88, "clear_radius": 0.10}]
    },
    "trim": {
      "visible": false,
      "segments": []
    }
  },
  "notes": "Wide shot with door on left; two wall segments visible"
}

RULES:
- cx, cy = center of a clear, unobstructed area on that surface (0-1 fractional coords)
- clear_radius = estimated radius (in fractional image units) that is free of obstacles
- Wall segments: identify EACH visually separate wall section (a door splits one wall into two)
- For wide shots, list all visible wall sections separately
- Ceiling: pick center of ceiling away from light fixtures
- Floor: pick open floor area, avoid rugs and furniture shadows
- Trim: ONLY if clearly visible as baseboards/door frames; set visible=false if uncertain
- Obstacles: list every door, window, large piece of furniture, anything that is NOT a flat wall/ceiling/floor
- If a surface is not visible, set visible=false and segments=[]"""


# ── Pass 2: Precise seed placement using scene map ────────────────────────────

def _build_seed_prompt(scene: dict) -> str:
    return f"""You already analyzed this room photo and produced this scene map:
{json.dumps(scene, indent=2)}

Now place precise segmentation seed points for each visible surface.

RULES:
1. Each seed [x, y] must land EXACTLY on the surface — not on furniture, door panels, or transitions.
2. Use the obstacle locations and clear_radius from the scene map to stay well away from obstacles.
3. For walls: place seeds in the center of each wall segment. If a door splits a wall, place one seed left of the door and one right of the door.
4. For ceiling: place seed away from light fixtures and ceiling fans.
5. For floor: place seed on open floor, not on rugs or near furniture feet.
6. For trim: place ONLY at y ≥ 0.85 (baseboard) or immediately on a door/window frame — never on furniture.
7. Each surface should have 3-5 seeds spread across it (not clustered).

Return ONLY valid JSON:
{{
  "wall": [[x1,y1], [x2,y2], [x3,y3]],
  "ceiling": [[x1,y1], [x2,y2]],
  "floor": [[x1,y1], [x2,y2]],
  "trim": [[x1,y1], [x2,y2]]
}}

Include ONLY surfaces where visible=true in the scene map.
Omit a key entirely if that surface is not visible."""


# ── Coverage bounds per surface ───────────────────────────────────────────────

_COVERAGE_BOUNDS = {
    "wall":    (0.04, 0.80),
    "ceiling": (0.04, 0.65),
    "floor":   (0.04, 0.65),
    "trim":    (0.003, 0.12),  # thin strips only — reject furniture
}


def _call_claude_vision(client, image_b64: str, prompt: str, max_tokens: int = 1024) -> str:
    """Single Claude Vision call. Returns raw text response."""
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=max_tokens,
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/jpeg", "data": image_b64},
                },
                {"type": "text", "text": prompt},
            ],
        }],
    )
    return response.content[0].text.strip()


def _parse_json(text: str) -> dict:
    """Extract and parse JSON from Claude response."""
    text = re.sub(r"^```[a-z]*\n?", "", text)
    text = re.sub(r"\n?```$", "", text).strip()
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        return json.loads(match.group())
    return json.loads(text)


def _segment_surface(pil: Image.Image, surface: str, seeds: list) -> tuple[str, str | None]:
    """
    Run SAM2 for one surface. Tries all provided seeds, picks the mask with
    the best coverage within expected bounds for that surface type.
    Never falls back to auto-segmentation for trim.
    """
    cov_min, cov_max = _COVERAGE_BOUNDS.get(surface, (0.04, 0.80))

    try:
        best_mask = None
        best_coverage = 0.0

        for seed in seeds[:5]:  # try up to 5 seeds
            sx, sy = float(seed[0]), float(seed[1])
            try:
                raw = _sam_segment(pil, sx, sy)
                arr = np.array(raw)
                coverage = float((arr > 127).sum()) / arr.size
                print(f"[segment-room] {surface} seed {seed} → {coverage:.2%} (bounds {cov_min:.1%}-{cov_max:.1%})")

                if cov_min <= coverage <= cov_max and coverage > best_coverage:
                    best_mask = raw
                    best_coverage = coverage
                elif coverage > cov_max:
                    print(f"[segment-room] {surface} seed {seed} rejected — too large ({coverage:.1%}), likely wrong object")
                elif coverage < cov_min:
                    print(f"[segment-room] {surface} seed {seed} rejected — too small ({coverage:.1%})")
            except Exception as e:
                print(f"[segment-room] SAM seed {seed} for {surface} failed: {e}")

        # Trim: never fall back (would grab walls or furniture)
        if best_mask is None and surface == "trim":
            print(f"[segment-room] trim: no valid mask found, skipping")
            return surface, None

        if best_mask is None:
            print(f"[segment-room] {surface}: no valid SAM mask, trying auto fallback")
            best_mask = _segment_auto(pil, surface)

        cleaned = _clean(best_mask)
        buf = io.BytesIO()
        cleaned.save(buf, format="PNG")
        arr = np.array(cleaned)
        coverage = float((arr > 127).sum()) / arr.size
        print(f"[segment-room] {surface}: final coverage={coverage:.2%}")
        return surface, base64.b64encode(buf.getvalue()).decode()

    except Exception as e:
        print(f"[segment-room] {surface} completely failed: {e}")
        if surface == "trim":
            return surface, None
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

        if "," in image_b64:
            image_b64 = image_b64.split(",", 1)[1]

        # Decode image
        try:
            image_bytes = base64.b64decode(image_b64)
            pil = Image.open(io.BytesIO(image_bytes))
            pil = ImageOps.exif_transpose(pil).convert("RGB")
        except Exception as e:
            return jsonify({"error": f"Image decode failed: {e}"}), 400

        client = _get_client()

        # ── Pass 1: Scene geometry analysis ──────────────────────────────────
        scene = {}
        try:
            raw1 = _call_claude_vision(client, image_b64, SCENE_ANALYSIS_PROMPT, max_tokens=800)
            scene = _parse_json(raw1)
            print(f"[segment-room] Scene analysis: shot_type={scene.get('shot_type')}, "
                  f"obstacles={len(scene.get('obstacles', []))}, "
                  f"notes={scene.get('notes', '')[:80]}")
        except Exception as e:
            print(f"[segment-room] Scene analysis failed: {e}")
            scene = {"shot_type": "unknown", "obstacles": [], "surfaces": {}, "notes": ""}

        # ── Pass 2: Precise seed placement ────────────────────────────────────
        seeds_by_surface: dict = {}
        try:
            seed_prompt = _build_seed_prompt(scene)
            raw2 = _call_claude_vision(client, image_b64, seed_prompt, max_tokens=512)
            seeds_by_surface = _parse_json(raw2)
            print(f"[segment-room] Seeds placed: {list(seeds_by_surface.keys())}")
        except Exception as e:
            print(f"[segment-room] Seed placement failed: {e}, using scene segment centers")

        # Fallback: derive seeds from scene analysis segment centers
        if not seeds_by_surface:
            surfaces_info = scene.get("surfaces", {})
            for surf, info in surfaces_info.items():
                if info.get("visible") and info.get("segments"):
                    seeds_by_surface[surf] = [
                        [seg["cx"], seg["cy"]] for seg in info["segments"]
                    ]

        # Final fallback: positional defaults
        if not seeds_by_surface.get("wall"):
            seeds_by_surface["wall"] = [[0.25, 0.45], [0.75, 0.45], [0.50, 0.40]]
        if not seeds_by_surface.get("ceiling"):
            seeds_by_surface["ceiling"] = [[0.50, 0.06], [0.25, 0.06], [0.75, 0.06]]
        if not seeds_by_surface.get("floor"):
            seeds_by_surface["floor"] = [[0.50, 0.92], [0.25, 0.92], [0.75, 0.92]]

        # ── Pass 3: Parallel SAM2 for all surfaces ────────────────────────────
        masks: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {
                executor.submit(_segment_surface, pil, surface, seeds): surface
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
                "scene": {
                    "shot_type": scene.get("shot_type", "unknown"),
                    "obstacle_count": len(scene.get("obstacles", [])),
                    "notes": scene.get("notes", ""),
                },
            },
            "error": None,
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
