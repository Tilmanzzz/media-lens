import logging
import json
import asyncpg

from .models import Episode

logger = logging.getLogger(__name__)


class Store:
    def __init__(self, conn_str: str):
        self.conn_str = conn_str
        self.pool: asyncpg.Pool = None

    async def connect(self):
        try:
            self.pool = await asyncpg.create_pool(
                dsn=self.conn_str, min_size=2, max_size=10
            )
            logger.info("Successfully established asyncpg PostgreSQL connection pool.")
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL via asyncpg: {e}")
            raise e

    async def close(self):
        if self.pool:
            await self.pool.close()

    async def get_episode_by_id(self, episode_id: str) -> Episode:
        query = """
            SELECT id, podcast_id, guid, title, audio_key, published_at, enclosure_url 
            FROM episodes WHERE id = $1
        """
        row = await self.pool.fetchrow(query, episode_id)
        if not row:
            raise Exception(f"Episode {episode_id} not found")

        return Episode(**row)

    async def set_transcript_key(self, episode_id: str, transcript_key: str) -> None:
        query = "UPDATE episodes SET transcript_key = $1 WHERE id = $2"
        status = await self.pool.execute(query, transcript_key, episode_id)

        if status == "UPDATE 0":
            raise Exception(f"No episode found with id: {episode_id}")

    async def create_pipeline_batch(self, stage: str, mode: str) -> str:
        query = """
            INSERT INTO pipeline_batches (stage, load_mode, status, start_ts, fin_ts)
            VALUES ($1::pipeline_stage, $2::load_mode, 'pending'::batch_status, NOW(), NOW())
            RETURNING id
        """
        batch_id = await self.pool.fetchval(query, stage, mode)
        return str(batch_id)

    async def complete_pipeline_batch(
        self, batch_id: str, status: str, notify_channel: str = None
    ) -> None:
        query = """
            UPDATE pipeline_batches
            SET status = $1::batch_status, fin_ts = NOW()
            WHERE id = $2
        """
        status_tag = await self.pool.execute(query, status, batch_id)
        if status_tag == "UPDATE 0":
            raise Exception(
                f"Failed to update pipeline batch status: batch_id {batch_id} not found"
            )

        if status == "success" and notify_channel:
            payload = json.dumps({"batch_id": batch_id})
            await self.pool.execute("SELECT pg_notify($1, $2)", notify_channel, payload)
            logger.info(f"Broadcasted '{notify_channel}' event for batch: {batch_id}")

    async def claim_batch_episodes(
        self,
        source_batch_id: str,
        new_batch_id: str,
    ) -> list[str] | None:
        """
        Atomically re-points all episodes from source_batch to new_batch and
        marks source_batch as 'consumed'.

        The two writes share a transaction so there is no observable state where
        episodes have moved but the source batch is still 'success' (or vice versa).
        Returns the claimed episode IDs; an empty list means another worker won the
        race and the new batch should be discarded.
        """
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                rows = await conn.fetch(
                    """
                    UPDATE episodes
                    SET batch_id = $1
                    WHERE batch_id = $2
                    RETURNING id
                    """,
                    new_batch_id,
                    source_batch_id,
                )
                if rows:
                    await conn.execute(
                        """
                        UPDATE pipeline_batches
                        SET status = 'consumed'::batch_status
                        WHERE id = $1
                        """,
                        source_batch_id,
                    )
                return [str(row["id"]) for row in rows]
