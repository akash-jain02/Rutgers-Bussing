FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY backend/requirements-runtime.txt /app/requirements.txt
RUN python -m pip install -r requirements.txt \
    && useradd --create-home --uid 10001 appuser

COPY backend/ /app/backend/
USER appuser
EXPOSE 8000

# Liveness only: transit-provider availability is checked separately.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)" || exit 1

# One worker keeps the existing in-memory cache shared across requests.
CMD ["python", "-m", "uvicorn", "backend.app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
