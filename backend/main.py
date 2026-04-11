"""
PaintMatch Flask Backend — Railway
ADDITIVE ONLY: register new blueprints below, never remove existing ones.
"""
import os
from flask import Flask, jsonify
from flask_cors import CORS
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
CORS(app)

app.config["MAX_CONTENT_LENGTH"] = 20 * 1024 * 1024  # 20MB max upload

# ---------------------------------------------------------------------------
# Blueprints — add new ones here, never remove
# ---------------------------------------------------------------------------
from routes.analyze_room import analyze_room_bp
from routes.render_room import render_room_bp
from routes.match_colors import match_colors_bp
from routes.segment_wall import segment_wall_bp

app.register_blueprint(analyze_room_bp)
app.register_blueprint(render_room_bp)
app.register_blueprint(match_colors_bp)
app.register_blueprint(segment_wall_bp)


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "paintmatch-api"})


# ---------------------------------------------------------------------------
# One-time seed endpoint — POST /admin/seed-colors  (remove after use)
# ---------------------------------------------------------------------------
@app.route("/admin/seed-colors", methods=["POST"])
def admin_seed_colors():
    import sys, pathlib
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    try:
        from seed.seed_colors_full import VENDOR_DATA, FINISH_OPTIONS
        from utils.supabase_client import get_supabase
        sb = get_supabase()
        total = 0
        results = {}
        for vendor, colors in VENDOR_DATA.items():
            seen = set()
            rows = []
            for name, code, hex_val, lrv, price, coverage in colors:
                if code in seen:
                    continue
                seen.add(code)
                rows.append({
                    "vendor": vendor, "color_name": name, "color_code": code,
                    "hex": hex_val, "lrv": lrv, "finish_options": FINISH_OPTIONS,
                    "price_per_gallon": price, "coverage_sqft": coverage,
                })
            for i in range(0, len(rows), 50):
                sb.table("paint_colors").upsert(rows[i:i+50], on_conflict="vendor,color_code").execute()
            total += len(rows)
            results[vendor] = len(rows)
        # Refresh in-memory cache
        from routes.match_colors import _color_cache
        import routes.match_colors as mc
        mc._color_cache = None
        return jsonify({"seeded": total, "by_vendor": results, "error": None})
    except Exception as e:
        return jsonify({"seeded": 0, "error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
