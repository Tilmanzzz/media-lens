from db.connection import get_pool
from psycopg.rows import dict_row


def connection_test():
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("INSERT INTO pipeline_runs DEFAULT VALUES RETURNING id")
            row = cur.fetchone()
            print(str(row["id"]))


if __name__ == "__main__":
    connection_test()
