from .connection import get_pool
from psycopg.rows import (
    dict_row,
)  # row["title"]... but could also use namedtuple_row (row.title...) as row format instead
# Einmal beim Start: Pool aufbauen


def get(episode_id: str):
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT * FROM episodes WHERE id = %s", (episode_id,))
            return cur.fetchone()
