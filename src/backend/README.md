# Audiolens Backend

Go REST API built with **Gin** + **Swagger**. Serves podcast episode data, topics, transcripts, fact-checks, and chat from PostgreSQL. Audio and cover images are served via MinIO presigned URLs.

## Endpoints

### Contract Endpoints (from `api-contracts.yml`)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/episodes` | Episode list — cursor pagination, free-text search (`?q=`, `?cursor=`, `?limit=`) |
| GET | `/api/v1/episodes/:id` | Episode detail (header area above tabs) |
| GET | `/api/v1/episodes/:id/topics` | Topics tab — returns 202 if analysis not ready |
| GET | `/api/v1/episodes/:id/transcript` | Transcript lines with `has_fact_flag` annotation |
| GET | `/api/v1/episodes/:id/fact-checks` | Fact-check claims for the sidebar |
| POST | `/api/v1/chat/conversations` | Create a new chat session |
| POST | `/api/v1/chat/conversations/:id/messages` | Send message — NDJSON streaming response (stubbed) |
| GET | `/api/v1/episodes/:id/sync` | SSE playback sync (stubbed) |

### Utility Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/health` | Health check (DB + MinIO) |

Swagger UI: **http://localhost:8080/swagger/index.html**

## Project Structure

```
cmd/server/main.go          # Entrypoint, routing, DI wiring
internal/
├── config/                  # Environment variable loading
├── database/                # PostgreSQL connection pool
├── storage/                 # MinIO client + presigned URLs
├── repository/              # Data access layer (interfaces + Postgres impl)
├── model/                   # Data models (DB + API contract schemas)
└── api/handlers/            # HTTP handlers
    ├── podcasts.go          # Episode list + detail, shared middleware & helpers
    ├── topics.go            # Topics tab
    ├── transcript.go        # Transcript tab
    ├── factchecks.go        # Fact-check sidebar
    ├── chat.go              # Chat session + NDJSON streaming
    ├── sync.go              # SSE playback sync
    └── health.go            # Health check
```

## Run

```bash
# Via Docker (from project root)
docker compose up -d postgres minio backend

# Local development
cd src/backend
make run
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_URL` | ✅ | — | PostgreSQL connection string |
| `MINIO_USER` | ✅ | — | MinIO access key |
| `MINIO_PASS` | ✅ | — | MinIO secret key |
| `MINIO_ENDPOINT` | — | `minio:9000` | MinIO host:port |
| `BACKEND_PORT` | — | `:8080` | Server listen address |
| `CORS_ORIGINS` | — | `http://localhost:3000` | Allowed origins (comma-separated) |
