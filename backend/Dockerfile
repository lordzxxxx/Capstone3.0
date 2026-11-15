# Production image for the FastAPI guidance/OCR service.
# Build context must be backend/ so training data and the local virtualenv are
# excluded by .dockerignore.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/tmp/huggingface \
    PORT=8080 \
    WEB_CONCURRENCY=1

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      libgl1 \
      libglib2.0-0 \
      libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN python -m pip install --upgrade pip \
    && python -m pip install -r requirements.txt

COPY app ./app
COPY firebase ./firebase
COPY models ./models

RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && mkdir -p /tmp/huggingface \
    && chown -R appuser:appuser /app /tmp/huggingface
USER appuser

CMD ["sh", "-c", "exec uvicorn app.api:app --host 0.0.0.0 --port ${PORT} --workers ${WEB_CONCURRENCY}"]
