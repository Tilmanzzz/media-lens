import os
from pathlib import Path
from dotenv import load_dotenv
from psycopg_pool import ConnectionPool


_pool = None

dotenv_path = Path(__file__).parent.parent.parent / ".env"
load_dotenv(dotenv_path)

dsn = os.getenv("POSTGRES_URL")
if not dsn:
    raise RuntimeError("POSTGRES_URL is not set")


def get_pool():
    global _pool
    if _pool is None:
        _pool = ConnectionPool(
            min_size=1,
            max_size=5,
            conninfo=dsn,
        )
        _pool.open(wait=True)
    return _pool
