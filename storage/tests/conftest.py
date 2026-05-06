import pytest
import uuid
from psycopg_pool import ConnectionPool
from psycopg.rows import dict_row
from dotenv import load_dotenv, find_dotenv
import os


load_dotenv(find_dotenv())
print("conftest loaded")


@pytest.fixture(scope="session")
def pool():
    dsn = os.getenv("POSTGRES_URL")
    print(f"DSN: {dsn}")
    if not dsn:
        raise RuntimeError("POSTGRES_URL is not set")
    p = ConnectionPool(conninfo=dsn, min_size=1, max_size=3, open=False)
    p.open(wait=True)
    yield p
    p.close()


@pytest.fixture
def conn(pool):
    """Each test gets a connection that is rolled back afterwards."""
    with pool.connection() as c:
        c.autocommit = False
        yield c
        c.rollback()


@pytest.fixture
def pipeline_run_id(conn) -> uuid.UUID:  # Update type hint
    """Creates a pipeline_run row and returns its id for use in episode tests."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("INSERT INTO pipeline_runs DEFAULT VALUES RETURNING id")
        row = cur.fetchone()
        return row["id"]  # Remove the str() cast here


if __name__ == "__main__":
    pass
