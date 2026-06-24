# src/02_processing/Dockerfile
FROM python:3.13-slim-bookworm AS builder
WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV UV_PROJECT_ENVIRONMENT=/app/.venv
ENV UV_COMPILE_BYTECODE=1
ENV UV_PYTHON=python3.13
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
	uv sync --frozen --no-install-project --no-dev

FROM python:3.13-slim-bookworm AS runtime
WORKDIR /app

# Install ffmpeg for emotion_scoring audio extraction
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
	&& rm -rf /var/lib/apt/lists/*

RUN groupadd -r appuser && useradd -r -g appuser appuser

COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Copy shared internal database models/utils
COPY internal/python/ /app/internal/python/

# Copy the entire processing context
COPY 02_processing/common/ /app/src/02_processing/common/
COPY 02_processing/silver_enriched/ /app/src/02_processing/silver_enriched/
COPY 02_processing/*.py /app/src/02_processing/
COPY 02_processing/*.json /app/src/02_processing/

# Set working directory to where the scripts expect to run
WORKDIR /app/src/02_processing/silver_enriched/

# Run as non-root user
USER appuser

# Orchestrator is the entrypoint
ENTRYPOINT ["python", "processing_pipeline/00_pipeline_processing_runner.py"]
