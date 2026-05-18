import logging
import json
from typing import List
from psycopg_pool import AsyncConnectionPool
from psycopg.rows import class_row

from .models import Episode, TranscriptSegment

logger = logging.getLogger(__name__)


class Store:
    def __init__(self, conn_str: str):
        """Initializes the async connection pool."""
        self.pool = AsyncConnectionPool(conninfo=conn_str, min_size=2, max_size=10)
        self.conn_str = conn_str

    async def connect(self):
        """Explicitly opens the connection pool."""
        try:
            await self.pool.open()
            logger.info("Successfully established PostgreSQL connection pool.")
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL: {e}")
            raise e

    async def close(self):
        """Gracefully close the connection pool."""
        await self.pool.close()

    async def get_episode_by_id(self, episode_id: str) -> Episode:
        """Fetches a single episode by its primary key (UUID)."""
        query = """
            SELECT id, podcast_id, guid, title, audio_key, status, published_at, enclosure_url 
            FROM episodes WHERE id = %s
        """
        async with self.pool.connection() as conn:
            # class_row acts exactly like pgxscan, mapping the row to the Pydantic model
            async with conn.cursor(row_factory=class_row(Episode)) as cur:
                await cur.execute(query, (episode_id,))
                ep = await cur.fetchone()
                if not ep:
                    raise Exception(f"Episode {episode_id} not found")
                return ep

    async def mark_pending_sectioning(self, episode_id: str) -> None:
        """Updates the episode status to pending_sectioning."""
        query = "UPDATE episodes SET status = 'pending_sectioning' WHERE id = %s"
        async with self.pool.connection() as conn:
            async with conn.cursor() as cur:
                await cur.execute(query, (episode_id,))
                if cur.rowcount == 0:
                    raise Exception(f"No episode found with id: {episode_id}")
            # Python requires explicit commits for updates/inserts
            await conn.commit()

    async def mark_pending_transcription(self, episode_id: str) -> None:
        """Updates the episode status to pending_transcription."""
        query = "UPDATE episodes SET status = 'pending_transcription' WHERE id = %s"
        async with self.pool.connection() as conn:
            async with conn.cursor() as cur:
                await cur.execute(query, (episode_id,))
                if cur.rowcount == 0:
                    raise Exception(f"No episode found with id: {episode_id}")
            await conn.commit()

    async def set_transcript_key(self, episode_id: str, transcript_key: str) -> None:
        """Sets the transcript_key for an episode."""
        query = "UPDATE episodes SET transcript_key = %s WHERE id = %s"
        async with self.pool.connection() as conn:
            async with conn.cursor() as cur:
                await cur.execute(query, (transcript_key, episode_id))
                if cur.rowcount == 0:
                    raise Exception(f"No episode found with id: {episode_id}")
            await conn.commit()

    async def insert_transcript_segments(
        self, episode_id: str, segments: List[TranscriptSegment]
    ) -> None:
        """Bulk inserts transcript segments into the database efficiently."""
        query = """
            INSERT INTO transcript_segments (episode_id, start_time, end_time, text, words)
            VALUES (%s, %s, %s, %s, %s)
        """

        # Prepare parameters as a list of tuples
        params = []
        for seg in segments:
            # Dump the list of Word Pydantic models into a JSON string for the JSONB column
            words_json = (
                json.dumps([w.model_dump() for w in seg.words]) if seg.words else None
            )
            params.append((episode_id, seg.start, seg.end, seg.text, words_json))

        async with self.pool.connection() as conn:
            async with conn.cursor() as cur:
                # executemany automatically pipelines the inserts
                await cur.executemany(query, params)
            await conn.commit()
