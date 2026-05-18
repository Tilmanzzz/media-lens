FROM python:3.13-slim AS builder

WORKDIR /app

# Copy uv binaries from the official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install build dependencies and runtime audio tools
RUN apt-get update && apt-get install -y --no-install-recommends \
	build-essential \
	ffmpeg \
	&& rm -rf /var/lib/apt/lists/*

ENV UV_PROJECT_ENVIRONMENT=/app/.venv
ENV UV_COMPILE_BYTECODE=1

# Since the build context is ./src, these are right at the root level
COPY pyproject.toml uv.lock ./

# Install dependencies using the cache mount for speed
RUN --mount=type=cache,target=/root/.cache/uv \
	uv sync --frozen --no-install-project --no-dev

FROM python:3.13-slim AS runtime

WORKDIR /app

# Re-install ffmpeg for the runtime environment (required by faster-whisper)
RUN apt-get update && apt-get install -y --no-install-recommends \
	ffmpeg \
	&& rm -rf /var/lib/apt/lists/*

# Copy the lightweight virtual environment from the builder stage
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Copy the actual application source paths
COPY internal/python/ /app/internal/python/
COPY 02_processing/transcription/main.py /app/main.py

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]
