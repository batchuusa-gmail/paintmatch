"""
POST /api/segment-room
Room surface segmentation — hybrid approach for maximum accuracy.

Pipeline:
  1. Claude Vision: one call, identifies wall seeds and obstacles (~5s).
  2. Ceiling + Floor: pure geometric + color-dominance (no SAM2, instant).
  3. Wall: SAM2 interactive mode with negative seeds on ceiling/floor regions.
  4. Trim: SAM2 with tight geometric clip to bottom 20%.

Advantages over pure SAM2:
  - Ceiling/floor never bleed into walls (geometric zones are hard boundaries).
  - Wall SAM2 uses negative points so it avoids ceiling/floor even on same-color rooms.
  - Total latency: ~15-25s (vs 40s before — 2 fewer SAM2 calls).
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

from routes.segment_wall import _sam_segment, _segment_auto, _clean, _resize_to, _upload_to_replicate

segment_room_bp = Blueprint("segment_room", __name__)

_anthropic_client = None


def _get_client() -> anthropic.Anthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _anthropic_client


# Only ask Claude for wall seeds — ceiling/floor handled geometrically.
SEED_PROMPT = """Analyze this room photo and return seed coordinates for wall segmentation.

Step 1 — Map obstacles: note every door, window, large furniture piece. Record approximate center (cx, cy).

Step 2 — Place 3 wall seed points in obstacle-free zones.
If a door splits the wall: place one seed LEFT and one RIGHT of the door.
Seeds must be on flat, unobstructed wall surface (not furniture, not door panels, not trim).

Return ONLY valid JSON:
{
  "obstacles": [
    {"type": "door", "cx": 0.40, "cy": 0.55, "w": 0.15, "h": 0.50}
  ],
  "wall": [[x1,y1], [x2,y2], [x3,y3]],
  "trim": [[x1,y1], [x2,y2]]
}

Placement rules:
- wall seeds: y between 0.25–0.72, stay 0.12+ away from any obstacle cx
- trim seeds: y >= 0.88, on baseboard strip; omit key if no distinct trim visible
- Omit "trim" key entirely if no baseboard/molding is clearly visible"""


# Coverage bounds per surface
_COVERAGE_BOUNDS = {
    "wall":    (0.04, 0.75),
    "ceiling": (0.03, 0.55),
    "floor":   (0.03, 0.55),
    "trim":    (0.003, 0.10),
}

_SAM_TIMEOUT_S = 30   # per wall/trim surface
_SAM2_VERSION  = "fe97b453a6455861e3bac769b441ca1f1086110da7466dbb65cf1eecfd60dc83"
_WORK_SIZE     = 1024


# ── Geometric mask (ceiling / floor) ─────────────────────────────────────────

def _geometric_mask(pil: Image.Image, surface: str) -> Image.Image | None:
    """
    Fast, reliable mask for ceiling and floor using geometric zones + color dominance.
    No SAM2 needed — these surfaces occupy predictable image regions.

    ceiling → top 26% of image
    floor   → bottom 24% of image
    """
    from skimage.segmentation import slic
    from skimage.util import img_as_float
    from skimage.color import rgb2lab

    w, h = pil.size
    scale = 512 / max(w, h)
    small = pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    arr   = img_as_float(np.array(small))
    segs  = slic(arr, n_segments=200, compactness=10, sigma=1,
                 start_label=0, channel_axis=2)
    sh, sw = segs.shape

    if surface == "ceiling":
        r0, r1 = 0, int(sh * 0.26)
    else:  # floor
        r0, r1 = int(sh * 0.76), sh

    roi_labels = segs[r0:r1, :]
    if roi_labels.size == 0:
        return None

    # Find the dominant SLIC label in the geometric zone
    dominant = int(np.bincount(roi_labels.flatten()).argmax())
    dom_lab = rgb2lab(
        arr[segs == dominant].mean(axis=0).reshape(1, 1, 3)
    ).reshape(3)

    # Mark all labels with similar color — then clip to zone
    out = np.zeros((sh, sw), dtype=np.uint8)
    for lbl in range(int(segs.max()) + 1):
        px = arr[segs == lbl]
        if not len(px):
            continue
        lab = rgb2lab(px.mean(axis=0).reshape(1, 1, 3)).reshape(3)
        if np.linalg.norm(lab - dom_lab) < 16:
            out[segs == lbl] = 255

    # Hard geometric clip — ceiling/floor cannot go outside their zones
    if surface == "ceiling":
        out[r1:, :] = 0
    else:
        out[:r0, :] = 0

    result = Image.fromarray(out, "L").resize(pil.size, Image.NEAREST)
    return result


# ── SAM2 interactive mode (wall / trim) ──────────────────────────────────────

def _sam_segment_interactive(
    pil: Image.Image,
    seed_x: float,
    seed_y: float,
    negative_seeds: list | None = None,
) -> Image.Image:
    """
    SAM2 interactive point mode.
    Positive seed = surface we want.
    Negative seeds = surfaces to AVOID (ceiling/floor regions for wall segmentation).

    Falls back to SAM2 auto-segmentation if interactive mode fails.
    """
    import replicate
    import requests as req

    token = os.environ.get("REPLICATE_API_TOKEN") or os.environ.get("REPLICATE_API_KEY")
    if not token:
        raise RuntimeError("REPLICATE_API_TOKEN not set")

    work      = _resize_to(pil, _WORK_SIZE)
    image_url = _upload_to_replicate(work, token)
    ww, wh    = work.size
    client    = replicate.Client(api_token=token)

    # Build point arrays (pixel coordinates)
    points = [[int(seed_x * ww), int(seed_y * wh)]]
    labels = [1]  # positive

    if negative_seeds:
        for nx, ny in negative_seeds[:4]:
            points.append([int(nx * ww), int(ny * wh)])
            labels.append(0)  # negative

    print(f"[sam-interactive] pos=({seed_x:.2f},{seed_y:.2f}) neg_count={len(negative_seeds or [])}")

    try:
        output = client.run(
            f"meta/sam-2:{_SAM2_VERSION}",
            input={
                "image":         image_url,
                "input_points":  points,
                "input_labels":  labels,
                "use_m2m":       True,
            },
        )

        # Interactive mode returns "masks" (list of URLs) + "scores"
        masks = output.get("masks", [])
        if not masks:
            raise RuntimeError("SAM2 interactive returned no masks")

        scores  = output.get("scores", [1.0] * len(masks))
        best_i  = int(np.argmax(scores)) if scores else 0
        best_url = masks[best_i % len(masks)]

        resp = req.get(str(best_url), timeout=30)
        resp.raise_for_status()
        m = Image.open(io.BytesIO(resp.content)).convert("L")
        if m.size != pil.size:
            m = m.resize(pil.size, Image.NEAREST)
        return m

    except Exception as e:
        print(f"[sam-interactive] failed ({e}), falling back to auto-seg")
        # Fall back to auto-segmentation
        return _sam_segment(pil, seed_x, seed_y)


# ── Geometric clip (hard boundary after SAM2) ─────────────────────────────────

def _geometric_clip(mask: Image.Image, surface: str) -> Image.Image:
    """
    Hard-clip SAM2 output to the physical region of each surface.
    Applied after SAM2 as a safety net — prevents any residual bleed.
    """
    arr = np.array(mask).copy()
    h   = arr.shape[0]

    if surface == "ceiling":
        arr[int(h * 0.30):, :] = 0
    elif surface == "floor":
        arr[:int(h * 0.70), :] = 0
    elif surface == "wall":
        arr[:int(h * 0.10), :] = 0   # remove ceiling band
        arr[int(h * 0.90):, :] = 0   # remove floor band
    elif surface == "trim":
        arr[:int(h * 0.76), :] = 0   # baseboard lives near floor

    return Image.fromarray(arr, "L")


# ── Per-surface segmentation ──────────────────────────────────────────────────

def _segment_surface(pil: Image.Image, surface: str, seeds: list) -> tuple[str, str | None]:
    """
    Dispatch to the right strategy per surface:
      ceiling/floor → geometric mask (fast, no SAM2)
      wall          → SAM2 interactive with negative seeds on ceiling + floor regions
      trim          → SAM2 auto with tight geometric clip
    """
    cov_min, cov_max = _COVERAGE_BOUNDS.get(surface, (0.04, 0.75))

    # ── Ceiling / Floor: geometric only ──────────────────────────────────────
    if surface in ("ceiling", "floor"):
        print(f"[seg-room] {surface}: geometric zone (no SAM2)")
        try:
            mask = _geometric_mask(pil, surface)
            if mask is None:
                return surface, None
            arr      = np.array(mask)
            coverage = float((arr > 127).sum()) / arr.size
            print(f"[seg-room] {surface} geometric coverage={coverage:.1%}")
            if coverage < cov_min:
                print(f"[seg-room] {surface} coverage too low, skipping")
                return surface, None
            # Cap coverage — clip if > max (prevents capturing everything)
            if coverage > cov_max:
                mask = _geometric_clip(mask, surface)
            cleaned = _clean(mask)
            buf = io.BytesIO()
            cleaned.save(buf, format="PNG")
            return surface, base64.b64encode(buf.getvalue()).decode()
        except Exception as e:
            print(f"[seg-room] {surface} geometric failed: {e}")
            return surface, None

    # ── Wall: SAM2 interactive with negative seeds ────────────────────────────
    if surface == "wall":
        # Negative seeds: top band (ceiling) + bottom band (floor)
        neg_seeds = [
            (0.25, 0.05), (0.75, 0.05),   # ceiling corners
            (0.25, 0.94), (0.75, 0.94),   # floor corners
        ]
        best_mask     = None
        best_coverage = 0.0

        for seed in seeds[:3]:
            sx, sy = float(seed[0]), float(seed[1])
            try:
                raw     = _sam_segment_interactive(pil, sx, sy, neg_seeds)
                clipped = _geometric_clip(raw, "wall")
                arr     = np.array(clipped)
                coverage = float((arr > 127).sum()) / arr.size
                print(f"[seg-room] wall seed ({sx:.2f},{sy:.2f}) → {coverage:.1%}")
                if cov_min <= coverage <= cov_max and coverage > best_coverage:
                    best_mask     = clipped
                    best_coverage = coverage
            except Exception as e:
                print(f"[seg-room] wall SAM failed for seed {seed}: {e}")

        if best_mask is None:
            print(f"[seg-room] wall: no SAM mask, using geometric fallback")
            try:
                best_mask = _geometric_clip(_segment_auto(pil, "wall"), "wall")
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

    # ── Trim: SAM2 auto + tight geometric clip ────────────────────────────────
    if surface == "trim":
        best_mask     = None
        best_coverage = 0.0

        for seed in seeds[:3]:
            sx, sy = float(seed[0]), float(seed[1])
            try:
                raw     = _sam_segment(pil, sx, sy)
                clipped = _geometric_clip(raw, "trim")
                arr     = np.array(clipped)
                coverage = float((arr > 127).sum()) / arr.size
                print(f"[seg-room] trim seed ({sx:.2f},{sy:.2f}) → {coverage:.1%}")
                if cov_min <= coverage <= cov_max and coverage > best_coverage:
                    best_mask     = clipped
                    best_coverage = coverage
            except Exception as e:
                print(f"[seg-room] trim SAM failed for seed {seed}: {e}")

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

        # ── Claude Vision: wall seeds + obstacles ─────────────────────────────
        seeds_by_surface: dict = {}
        try:
            client   = _get_client()
            response = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=500,
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
            raw   = response.content[0].text.strip()
            raw   = re.sub(r"^```[a-z]*\n?", "", raw)
            raw   = re.sub(r"\n?```$", "", raw).strip()
            match = re.search(r"\{.*\}", raw, re.DOTALL)
            parsed = json.loads(match.group() if match else raw)

            seeds_by_surface = {
                k: v for k, v in parsed.items()
                if k != "obstacles" and isinstance(v, list)
            }
            obstacles = parsed.get("obstacles", [])
            print(f"[seg-room] obstacles={len(obstacles)} seeds={list(seeds_by_surface.keys())}")

        except Exception as e:
            print(f"[seg-room] Claude seed extraction failed: {e}")

        # ── Ensure wall seeds exist; always run ceiling + floor geometrically ──
        if not seeds_by_surface.get("wall"):
            seeds_by_surface["wall"] = [[0.25, 0.45], [0.75, 0.45], [0.50, 0.40]]

        # Ceiling and floor always use geometric — pass empty seeds (unused)
        seeds_by_surface["ceiling"] = []
        seeds_by_surface["floor"]   = []

        # ── Parallel execution: ceiling/floor instant, wall/trim use SAM2 ──────
        # Ceiling + floor resolve in <1s; wall/trim take ~20s.
        # ThreadPool handles all four; ceiling/floor free up threads quickly.
        masks: dict[str, str] = {}
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {
                executor.submit(_segment_surface, pil, surface, seeds): surface
                for surface, seeds in seeds_by_surface.items()
            }
            # Total timeout: ceiling/floor + wall + trim (wall dominates)
            total_timeout = _SAM_TIMEOUT_S * 2 + 5   # ~65s max
            for future in as_completed(futures, timeout=total_timeout):
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
