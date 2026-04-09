# Media-Lens Backend

Go REST API built with **Gin** + **Swagger**. Serves podcast metadata from PostgreSQL and audio streaming via MinIO presigned URLs.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/health` | Health check (DB + MinIO) |
| GET | `/api/v1/podcasts` | List distinct podcasts with episode counts |
| GET | `/api/v1/episodes` | List episodes (`?podcast_id=` optional) |
| GET | `/api/v1/episodes/:id` | Episode details + sections |
| GET | `/api/v1/episodes/:id/sections` | Sections with sentiment & topics |
| GET | `/api/v1/search?q=` | Text search across sections (`&limit=` optional) |
| GET | `/api/v1/audio-url/:id` | Presigned MinIO URL for audio streaming |

Swagger UI: **http://localhost:8080/swagger/index.html**

## Project Structure

```
cmd/server/main.go          # Entrypoint, routing, DI wiring
internal/
├── config/                  # Environment variable loading
├── database/                # PostgreSQL connection pool
├── storage/                 # MinIO client + presigned URLs
├── repository/              # Data access layer (interfaces + Postgres impl)
├── model/                   # Data models (aligned to DB schema)
└── api/handlers/            # HTTP handlers
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
