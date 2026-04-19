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
from routes.estimate_dimensions import estimate_dimensions_bp
from routes.segment_room import segment_room_bp

app.register_blueprint(analyze_room_bp)
app.register_blueprint(render_room_bp)
app.register_blueprint(match_colors_bp)
app.register_blueprint(segment_wall_bp)
app.register_blueprint(estimate_dimensions_bp)
app.register_blueprint(segment_room_bp)


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "paintmatch-api", "build": "rest-client-v1"})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
