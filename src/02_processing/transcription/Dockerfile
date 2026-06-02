# ==========================================
# BUILDER STAGE
# ==========================================
FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

# Copy uv binaries from the official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# 1. Install prerequisites for adding PPAs
# 2. Add the deadsnakes PPA for Python 3.13
# 3. Install Python 3.13 and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
	software-properties-common dirmngr gpg-agent \
	&& add-apt-repository ppa:deadsnakes/ppa -y \
	&& apt-get update && apt-get install -y --no-install-recommends \
	python3.13 \
	python3.13-venv \
	python3.13-dev \
	build-essential \
	&& rm -rf /var/lib/apt/lists/*

ENV UV_PROJECT_ENVIRONMENT=/app/.venv
ENV UV_COMPILE_BYTECODE=1
# Force uv to use the newly installed Python 3.13
ENV UV_PYTHON=python3.13

# Since the build context is ./src, these are right at the root level
COPY pyproject.toml uv.lock ./

# Install dependencies using the cache mount for speed
RUN --mount=type=cache,target=/root/.cache/uv \
	uv sync --frozen --no-install-project --no-dev


# ==========================================
# RUNTIME STAGE
# ==========================================
FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Install the exact same Python 3.13 environment + ffmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
	software-properties-common dirmngr gpg-agent \
	&& add-apt-repository ppa:deadsnakes/ppa -y \
	&& apt-get update && apt-get install -y --no-install-recommends \
	python3.13 \
	python3.13-venv \
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

# The python binary inside the .venv automatically resolves to 3.13
CMD ["python", "main.py"]
