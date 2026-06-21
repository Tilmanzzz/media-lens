FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
RUN apt-get update && apt-get install -y --no-install-recommends \
	software-properties-common dirmngr gpg-agent \
	&& add-apt-repository ppa:deadsnakes/ppa -y \
	&& apt-get update && apt-get install -y --no-install-recommends \
	python3.13 python3.13-venv python3.13-dev build-essential \
	&& rm -rf /var/lib/apt/lists/*
ENV UV_PROJECT_ENVIRONMENT=/app/.venv
ENV UV_COMPILE_BYTECODE=1
ENV UV_PYTHON=python3.13
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
	uv sync --frozen --no-install-project --no-dev

FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
	software-properties-common dirmngr gpg-agent \
	&& add-apt-repository ppa:deadsnakes/ppa -y \
	&& apt-get update && apt-get install -y --no-install-recommends \
	python3.13 python3.13-venv ffmpeg \
	&& rm -rf /var/lib/apt/lists/*
COPY --chown=appuser:appuser --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
COPY internal/python/ /app/internal/python/
COPY 02_processing/common/ /app/common/
COPY 02_processing/transcription/main.py /app/main.py
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
CMD ["python", "main.py"]
