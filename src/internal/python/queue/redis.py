import logging
from typing import Tuple, Optional
import redis.asyncio as aioredis
from redis.exceptions import ResponseError

logger = logging.getLogger(__name__)

# Core Domain Constants matching your Go implementation
TRANSCRIPTION_STREAM = "transcription_stream"
TRANSCRIPTION_GROUP = "transcription_group"
SECTIONING_STREAM = "sectioning_stream"


class QueueClient:
    def __init__(self, redis_addr: str):
        """
        Initializes the Redis Client using a connection pool.
        Expects a format like 'localhost:6379' or an explicit redis:// URL.
        """
        if not redis_addr.startswith("redis://"):
            redis_url = f"redis://{redis_addr}"
        else:
            redis_url = redis_addr

        # Create an async connection pool
        self.pool = aioredis.ConnectionPool.from_url(
            redis_url,
            decode_responses=True,  # Automatically decodes Redis bytes to Python strings
            max_connections=10,
        )
        self.rdb = aioredis.Redis(connection_pool=self.pool)

    async def initialize(self):
        """
        Ensures the required streams and consumer groups exist before consuming.
        """
        try:
            # id="0" tells the group to track from the beginning of the stream
            # mkstream=True creates the underlying stream if it doesn't exist
            await self.rdb.xgroup_create(
                name=TRANSCRIPTION_STREAM,
                groupname=TRANSCRIPTION_GROUP,
                id="0",
                mkstream=True,
            )
            logger.info(
                f"Initialized consumer group '{TRANSCRIPTION_GROUP}' on '{TRANSCRIPTION_STREAM}'"
            )
        except ResponseError as e:
            if "BUSYGROUP" in str(e):
                # BUSYGROUP means the group already exists, which is the expected steady-state
                pass
            else:
                logger.error(f"Failed to initialize Redis consumer groups: {e}")
                raise e

    async def close(self):
        """Gracefully disconnects and flushes the pool connections."""
        await self.pool.disconnect()

    async def dequeue_transcription(
        self, consumer_id: str
    ) -> Tuple[Optional[str], Optional[str]]:
        """
        Blocks and waits for a completely NEW message from the stream.
        Returns a tuple of (message_id, episode_id).
        Returns (None, None) if the connection times out without data.
        """
        try:
            # XREADGROUP GROUP group:transcription consumer_id BLOCK 2000 COUNT 1 STREAMS stream:transcription >
            response = await self.rdb.xreadgroup(
                groupname=TRANSCRIPTION_GROUP,
                consumername=consumer_id,
                streams={TRANSCRIPTION_STREAM: ">"},
                count=1,
                block=2000,  # Block for 2 seconds before releasing to check loop context/signals
            )

            if not response:
                return None, None

            # Unpack response format: [[stream_name, [(message_id, field_dict)]]]
            _, messages = response[0]
            message_id, fields = messages[0]

            episode_id = fields.get("episode_id")
            return message_id, episode_id

        except Exception as e:
            logger.error(f"Failed to dequeue from transcription stream: {e}")
            raise e

    async def claim_stale_transcription(
        self, consumer_id: str, min_idle_ms: int = 300000
    ) -> Tuple[Optional[str], Optional[str]]:
        """
        Scans the Pending Entries List (PEL) for tasks that have been running
        longer than min_idle_ms (default 5 minutes) and forcefully claims them.
        """
        try:
            # XAUTOCLAIM stream:transcription group:transcription consumer_id 300000 0-0 COUNT 1
            # Returns: (next_start_id, [messages], [deleted_ids])
            _, claimed_messages, _ = await self.rdb.xautoclaim(
                name=TRANSCRIPTION_STREAM,
                groupname=TRANSCRIPTION_GROUP,
                consumername=consumer_id,
                min_idle_time=min_idle_ms,
                start_id="0-0",
                count=1,
            )

            if not claimed_messages:
                return None, None

            message_id, fields = claimed_messages[0]
            episode_id = fields.get("episode_id")
            return message_id, episode_id

        except Exception as e:
            logger.error(f"Failed to execute xautoclaim: {e}")
            return None, None

    async def ack_transcription(self, message_id: str) -> None:
        """Acknowledges the message completion, removing it from the PEL."""
        try:
            await self.rdb.xack(TRANSCRIPTION_STREAM, TRANSCRIPTION_GROUP, message_id)
        except Exception as e:
            logger.error(f"Failed to acknowledge message {message_id}: {e}")
            raise e

    async def enqueue_sectioning(self, episode_id: str) -> None:
        """Pushes the computed episode forward into the sectioning queue pipeline."""
        try:
            # XADD stream:sectioning * episode_id <id>
            await self.rdb.xadd(
                name=SECTIONING_STREAM,
                fields={"episode_id": episode_id},
                id="*",  # Automatically generate standard timestamp-based Redis ID
            )
        except Exception as e:
            logger.error(
                f"Failed to enqueue to sectioning stream for episode {episode_id}: {e}"
            )
            raise e
