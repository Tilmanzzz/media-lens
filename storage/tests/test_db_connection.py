from psycopg import Connection
from psycopg_pool import ConnectionPool

# Adjust this import path if your root package is named differently

from ..db.connection import get_pool


def test_conftest_pool_initialization(pool):
    """Verify that the test session pool initializes correctly."""
    assert isinstance(pool, ConnectionPool)


def test_conftest_conn_can_query(conn):
    """Verify that the test connection yields and can execute a simple query."""
    assert isinstance(conn, Connection)
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
        result = cur.fetchone()
        assert result == (1,)


def test_app_connection_pool():
    """Verify that the application's connection.py pool initializes and queries."""
    app_pool = get_pool()
    assert isinstance(app_pool, ConnectionPool)
    with app_pool.connection() as c:
        with c.cursor() as cur:
            cur.execute("SELECT 1")
            result = cur.fetchone()
            assert result == (1,)


def test_pipeline_run_id_fixture(pipeline_run_id):
    """Verify the pipeline fixture inserts a record and returns an ID."""
    assert pipeline_run_id is not None
