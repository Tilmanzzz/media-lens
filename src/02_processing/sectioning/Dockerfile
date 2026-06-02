# ==========================================
# BUILDER STAGE
# ==========================================
FROM python:3.13-slim-bookworm AS builder

WORKDIR /app

# Copy uv binaries from the official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_PROJECT_ENVIRONMENT=/app/.venv
ENV UV_COMPILE_BYTECODE=1
ENV UV_PYTHON=python3.13

# Since the build context is ./src, these are right at the root level
COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
	uv sync --frozen --no-install-project --no-dev

# ==========================================
# RUNTIME STAGE
# ==========================================
FROM python:3.13-slim-bookworm AS runtime

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

COPY internal/python/ /app/internal/python/
COPY 02_processing/sectioning/main.py /app/main.py

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]
