"""
POST /segment-wall
Uses Meta SAM 2 via Replicate (meta/sam-2).

Strategy (in priority order):
1. SAM auto-segmentation → pick masks with:
   a. Area 4%–70% of image (excludes switches/frames/pillows AND full-scene masks)
   b. Among those covering the tap point: sort by color distance to tap pixel
   c. Merge all masks within distance threshold to reconstruct fragmented walls
2. Radius search — if no mask at exact tap pixel, scan a 5% radius
3. BFS fallback — flood-fill from tap using SLIC superpixels + color similarity

Root fix: the previous "largest mask at tap point" picked switches/frames because
SAM fragments walls into many small pieces each < 1%, while a switch is one clean 1%
mask that happens to be the only mask at the exact tap pixel.
"""
import base64
import io
import json
import os
from collections import deque

import numpy as np
import requests as req
from flask import Blueprint, jsonify, request
from PIL import Image, ImageFilter, ImageOps

segment_wall_bp = Blueprint("segment_wall", __name__)

SAM2_VERSION = "fe97b453a6455861e3bac769b441ca1f1086110da7466dbb65cf1eecfd60dc83"
WORK_SIZE    = 1024   # longest edge — SAM works best at higher res

# Area bounds: walls/ceilings/floors are always in this range of image pixels.
# Switches, outlets, frames, pillows are < 3%.
# Full-scene/background masks (the "entire room") are > 70%.
MIN_AREA_FRAC = 0.04   # 4% minimum
MAX_AREA_FRAC = 0.70   # 70% maximum

# How many pixels around the tap to search if no mask covers the exact tap point
SEARCH_RADIUS_FRAC = 0.05  # 5% of shortest image dimension

# Color merge: masks whose avg color is within this RGB Euclidean distance
# of the tap pixel's color are treated as "same surface" and merged
COLOR_MERGE_THRESH = 35.0   # out of 255 per channel (≈ 20 Delta-E equivalent)


def _resize_to(pil: Image.Image, max_edge: int) -> Image.Image:
    w, h = pil.size
    scale = min(1.0, max_edge / max(w, h))
    if scale < 1.0:
        return pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    return pil


def _upload_to_replicate(pil: Image.Image, token: str) -> str:
    """Upload image bytes to Replicate file API, return URL."""
    buf = io.BytesIO()
    pil.save(buf, format="JPEG", quality=92)
    buf.seek(0)
    resp = req.post(
        "https://api.replicate.com/v1/files",
        headers={"Authorization": f"Bearer {token}"},
        files={"content": ("image.jpg", buf, "image/jpeg")},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["urls"]["get"]


def _rgb_dist(a: np.ndarray, b: np.ndarray) -> float:
    """Euclidean distance in RGB space (values 0–255)."""
    return float(np.linalg.norm(a.astype(float) - b.astype(float)))


def _sam_segment(pil: Image.Image, seed_x: float, seed_y: float) -> Image.Image:
    """
    Run SAM 2 auto-segmentation, then pick the mask that best represents
    the large flat surface (wall/ceiling/floor) at the tap point.

    Selection logic:
    1. Download all SAM masks.
    2. Reject masks outside [MIN_AREA_FRAC, MAX_AREA_FRAC] — removes small objects.
    3. Among remaining masks that cover the tap pixel exactly:
       - Score by color distance (mask avg color vs tap pixel color)
       - Merge all masks whose avg color is close to the tap pixel's color
    4. If no large mask covers the exact tap pixel, search SEARCH_RADIUS_FRAC radius.
    5. Last resort: BFS flood-fill.
    """
    import replicate

    token = os.environ.get("REPLICATE_API_TOKEN") or os.environ.get("REPLICATE_API_KEY")
    if not token:
        raise RuntimeError("REPLICATE_API_TOKEN not set")

    work = _resize_to(pil, WORK_SIZE)
    image_url = _upload_to_replicate(work, token)

    client = replicate.Client(api_token=token)

    # Lower thresholds vs. previous version so walls (which have variable
    # texture/lighting) are more likely to be represented as individual masks
    output = client.run(
        f"meta/sam-2:{SAM2_VERSION}",
        input={
            "image":                  image_url,
            "points_per_side":        32,
            "pred_iou_thresh":        0.80,   # was 0.88 — more permissive
            "stability_score_thresh": 0.85,   # was 0.92 — more permissive
            "use_m2m":                True,
        },
    )

    individual_masks = output.get("individual_masks", [])
    if not individual_masks:
        raise RuntimeError("SAM returned no masks")

    ww, wh = work.size
    tx = int(seed_x * ww)
    ty = int(seed_y * wh)
    total_pix = ww * wh

    # RGB value at the exact tap pixel (used for color-distance scoring)
    work_rgb = np.array(work.convert("RGB"))
    tap_rgb  = work_rgb[ty, tx].astype(float)

    # Download all masks once and compute stats
    mask_data = []  # (area_frac, arr, mask_pil, avg_rgb)
    for mask_url in individual_masks:
        try:
            resp = req.get(str(mask_url), timeout=30)
            resp.raise_for_status()
            m = Image.open(io.BytesIO(resp.content)).convert("L")
        except Exception:
            continue
        if m.size != work.size:
            m = m.resize(work.size, Image.NEAREST)
        arr      = np.array(m)
        area     = int((arr > 127).sum())
        area_frac = area / total_pix
        # Average color of ALL pixels inside this mask
        px       = work_rgb[arr > 127]
        avg_rgb  = px.mean(axis=0) if len(px) > 0 else np.zeros(3)
        mask_data.append((area_frac, arr, m, avg_rgb))

    # ── Step 1: candidates that cover the tap pixel AND are the right size ─────
    candidates = [
        (af, arr, m, avg) for af, arr, m, avg in mask_data
        if arr[ty, tx] > 127
        and MIN_AREA_FRAC <= af <= MAX_AREA_FRAC
    ]

    if candidates:
        # Sort by color distance to tap pixel — mask whose avg color is
        # most similar to tap pixel is most likely the same surface
        candidates.sort(key=lambda x: _rgb_dist(x[3], tap_rgb))

        # Merge all candidates whose avg color is within COLOR_MERGE_THRESH
        # This reconstructs walls that SAM fragmented into multiple pieces
        base_color = candidates[0][3]
        union_arr  = np.zeros((wh, ww), dtype=np.uint8)
        merged     = 0
        for af, arr, m, avg in candidates:
            if _rgb_dist(avg, base_color) <= COLOR_MERGE_THRESH:
                union_arr = np.maximum(union_arr, (arr > 127).astype(np.uint8) * 255)
                merged += 1

        if merged > 0:
            merged_pil = Image.fromarray(union_arr, "L")
            return merged_pil.resize(pil.size, Image.NEAREST)

    # ── Step 2: no large mask at exact tap — search nearby ────────────────────
    search_r = max(10, int(min(ww, wh) * SEARCH_RADIUS_FRAC))
    y0 = max(0,  ty - search_r);  y1 = min(wh, ty + search_r)
    x0 = max(0,  tx - search_r);  x1 = min(ww, tx + search_r)

    # Find all large masks that are active anywhere in the search square,
    # sort by color similarity to tap pixel
    nearby = [
        (af, arr, m, avg) for af, arr, m, avg in mask_data
        if MIN_AREA_FRAC <= af <= MAX_AREA_FRAC
        and (arr[y0:y1, x0:x1] > 127).any()
    ]
    if nearby:
        nearby.sort(key=lambda x: _rgb_dist(x[3], tap_rgb))
        # Merge color-similar nearby masks
        base_color = nearby[0][3]
        union_arr  = np.zeros((wh, ww), dtype=np.uint8)
        for af, arr, m, avg in nearby:
            if _rgb_dist(avg, base_color) <= COLOR_MERGE_THRESH:
                union_arr = np.maximum(union_arr, (arr > 127).astype(np.uint8) * 255)
        if union_arr.max() > 0:
            return Image.fromarray(union_arr, "L").resize(pil.size, Image.NEAREST)

    # ── Step 3: BFS fallback ──────────────────────────────────────────────────
    raise RuntimeError("No suitable mask found — BFS fallback required")


# ─── BFS fallback ────────────────────────────────────────────────────────────

def _segment_bfs(pil: Image.Image, seed_x: float, seed_y: float) -> Image.Image:
    from skimage.segmentation import slic
    from skimage.util import img_as_float
    from skimage.color import rgb2lab

    w, h = pil.size
    scale = 512 / max(w, h)
    small = pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    arr   = img_as_float(np.array(small))
    segs  = slic(arr, n_segments=300, compactness=12, sigma=1,
                 start_label=0, channel_axis=2)
    sh, sw = segs.shape

    sy = max(0, min(int(seed_y * sh), sh - 1))
    sx = max(0, min(int(seed_x * sw), sw - 1))
    seed_lbl = int(segs[sy, sx])

    n = int(segs.max()) + 1

    def lab_mean(lbl):
        px = arr[segs == lbl]
        return rgb2lab(px.mean(axis=0).reshape(1, 1, 3)).reshape(3) if len(px) else None

    # Build adjacency
    adj = {i: set() for i in range(n)}
    for r in range(sh):
        for c in range(sw):
            lbl = int(segs[r, c])
            for dr, dc in ((0, 1), (1, 0)):
                nr, nc = r + dr, c + dc
                if 0 <= nr < sh and 0 <= nc < sw:
                    nb = int(segs[nr, nc])
                    if nb != lbl:
                        adj[lbl].add(nb); adj[nb].add(lbl)

    seed_lab = lab_mean(seed_lbl)
    visited  = {seed_lbl}
    queue    = deque([seed_lbl])
    selected = {seed_lbl}

    while queue:
        lbl = queue.popleft()
        for nb in adj[lbl]:
            if nb in visited:
                continue
            visited.add(nb)
            nb_lab = lab_mean(nb)
            if nb_lab is not None and np.linalg.norm(nb_lab - seed_lab) < 14:
                selected.add(nb); queue.append(nb)

    out = np.zeros((sh, sw), dtype=np.uint8)
    for lbl in selected:
        out[segs == lbl] = 255
    return Image.fromarray(out, "L").resize(pil.size, Image.NEAREST)


def _segment_auto(pil: Image.Image, surface: str) -> Image.Image:
    from skimage.segmentation import slic
    from skimage.util import img_as_float
    from skimage.color import rgb2lab

    w, h = pil.size
    scale = 512 / max(w, h)
    small = pil.resize((int(w * scale), int(h * scale)), Image.BILINEAR)
    arr   = img_as_float(np.array(small))
    segs  = slic(arr, n_segments=300, compactness=12, sigma=1,
                 start_label=0, channel_axis=2)
    sh, sw = segs.shape
    br = arr.mean(axis=2)

    if surface == "floor":
        r0, r1, c0, c1 = int(sh * .70), sh, 0, sw
        valid = br < 0.82
    elif surface == "ceiling":
        r0, r1, c0, c1 = 0, int(sh * .20), 0, sw
        valid = br > 0.30
    else:
        r0, r1, c0, c1 = int(sh * .15), int(sh * .80), int(sw * .08), int(sw * .92)
        valid = (br > 0.12) & (br < 0.88)

    roi = np.zeros((sh, sw), dtype=bool)
    roi[r0:r1, c0:c1] = True; roi &= valid
    labels = segs[roi]
    if not len(labels):
        labels = segs[r0:r1, c0:c1].flatten()

    dominant = int(np.bincount(labels).argmax())
    dom_lab  = rgb2lab(arr[segs == dominant].mean(axis=0).reshape(1, 1, 3)).reshape(3)

    out = np.zeros((sh, sw), dtype=np.uint8)
    for lbl in range(int(segs.max()) + 1):
        px = arr[segs == lbl]
        if not len(px):
            continue
        lab = rgb2lab(px.mean(axis=0).reshape(1, 1, 3)).reshape(3)
        if np.linalg.norm(lab - dom_lab) < 14:
            out[segs == lbl] = 255

    return Image.fromarray(out, "L").resize(pil.size, Image.NEAREST)


def _clean(mask: Image.Image) -> Image.Image:
    """
    Smooth mask edges without shrinking them.
    Previously used MinFilter (erosion) which ate wall boundaries — removed.
    Now uses blur + threshold only, producing clean edges without shrinkage.
    """
    b = mask.filter(ImageFilter.GaussianBlur(radius=2))
    return b.point(lambda p: 255 if p > 100 else 0)


# ─── Route ───────────────────────────────────────────────────────────────────

@segment_wall_bp.route("/segment-wall", methods=["POST"])
def segment_wall():
    data          = request.get_json(force=True, silent=True) or {}
    image_b64     = data.get("image")
    surface_param = data.get("surface", "wall").lower().split(",")[0].strip()
    seed_x        = data.get("seed_x")
    seed_y        = data.get("seed_y")

    if not image_b64:
        return jsonify({"data": None, "error": "Missing image"}), 400
    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception:
        return jsonify({"data": None, "error": "Invalid base64"}), 400

    try:
        pil = Image.open(io.BytesIO(image_bytes))
        pil = ImageOps.exif_transpose(pil).convert("RGB")
    except Exception as e:
        return jsonify({"data": None, "error": f"Image decode failed: {e}"}), 500

    method = "auto"
    try:
        if seed_x is not None and seed_y is not None:
            sx, sy = float(seed_x), float(seed_y)
            try:
                raw    = _sam_segment(pil, sx, sy)
                method = "sam2"
            except Exception as e:
                print(f"[segment-wall] SAM failed ({e}), BFS fallback")
                raw    = _segment_bfs(pil, sx, sy)
                method = "bfs_fallback"
        else:
            raw    = _segment_auto(pil, surface_param)
            method = "auto"
        cleaned = _clean(raw)
    except Exception as e:
        return jsonify({"data": None, "error": f"Segmentation failed: {e}"}), 500

    buf = io.BytesIO()
    cleaned.save(buf, format="PNG")
    mask_b64 = base64.b64encode(buf.getvalue()).decode()
    arr      = np.array(cleaned)
    coverage = float((arr > 127).sum()) / arr.size

    return jsonify({
        "data": {
            "mask":     mask_b64,
            "surface":  surface_param,
            "coverage": round(coverage, 3),
            "method":   method,
        },
        "error": None,
    })
