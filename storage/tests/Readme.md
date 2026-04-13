# Running the tests

These are integration tests that require a running PostgreSQL instance.

## Setup

Copy the root `.env.example` to `.env` and fill in your credentials, then start the database:

    docker compose up -d postgres

## Run

    uv run pytest tests/ -v

## Notes

- Tests are transactional — each test rolls back after running, so no data is left behind
- Tests will fail if POSTGRES_URL is not set in your .env
