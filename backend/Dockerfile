FROM python:3.11-slim

WORKDIR /app

# System deps needed by torch/Pillow
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ libgomp1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# ── Layer 1: heavy ML deps (cached unless these lines change) ──────────────
RUN pip install --no-cache-dir \
    torch==2.3.1+cpu \
    torchvision==0.18.1+cpu \
    --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir transformers==4.44.0

# ── Layer 2: remaining app deps ────────────────────────────────────────────
COPY requirements-base.txt .
RUN pip install --no-cache-dir -r requirements-base.txt

# ── Layer 3: app code ──────────────────────────────────────────────────────
COPY . .

CMD gunicorn main:app --bind 0.0.0.0:$PORT --workers 1 --timeout 180
