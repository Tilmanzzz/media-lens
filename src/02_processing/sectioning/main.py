import os
import sys
import json
import asyncio
import logging
import signal
import asyncpg
from typing import Any, Dict, List, Optional
from minio import Minio

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from internal.python.db.store import Store

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("segmenting_worker")

shutdown_event = asyncio.Event()
internal_task_queue: asyncio.Queue[str] = asyncio.Queue()

# Target wall-clock length for each section (seconds). Override via env var.
# ↳ swap section_transcript() below for topic- or embedding-based splitting.
SECTION_TARGET_DURATION_S: int = int(os.getenv("SECTION_DURATION_SECONDS", "300"))


def handle_exit_signals() -> None:
    logger.info("Received termination signal. Shutting down...")
    shutdown_event.set()


# ==============================================================================
# INFRASTRUCTURE & SETUP
# ==============================================================================


def init_minio_client() -> Minio:
    endpoint = (
        os.getenv("MINIO_ENDPOINT", "localhost:9000")
        .replace("http://", "")
        .replace("https://", "")
    )
    return Minio(
        endpoint,
        access_key=os.getenv("MINIO_USER", "minioadmin"),
        secret_key=os.getenv("MINIO_PASS", "minioadmin"),
        secure=False,
    )


async def postgres_listener_task(pg_url: str) -> None:
    """Listens for NOTIFY events on 'segmenting_ready' with heartbeat + auto-reconnect."""
    while not shutdown_event.is_set():
        conn = None
        try:
            conn = await asyncpg.connect(pg_url)

            def on_notification(connection, pid, channel, payload):
                try:
                    event = json.loads(payload)
                    if batch_id := event.get("batch_id"):
                        internal_task_queue.put_nowait(batch_id)
                except Exception as e:
                    logger.error(f"Failed to parse notification payload: {e}")

            await conn.add_listener("segmenting_ready", on_notification)
            logger.info("Listening on 'segmenting_ready'")

            while not shutdown_event.is_set():
                await asyncio.sleep(30)
                await conn.execute("SELECT 1")  # keep-alive ping

        except Exception as e:
            if not shutdown_event.is_set():
                logger.warning(f"Listener connection lost: {e}. Reconnecting in 5s...")
                await asyncio.sleep(5)
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass


async def queue_backlog_batches(store: Store) -> None:
    """Enqueues any transcription-success batches that this worker hasn't seen yet."""
    try:
        rows = await store.pool.fetch(
            """
            SELECT id FROM pipeline_batches
            WHERE stage = 'transcription' AND status = 'success'
            ORDER BY start_ts ASC
            """
        )
        for row in rows:
            internal_task_queue.put_nowait(str(row["id"]))
        if rows:
            logger.info(f"Queued {len(rows)} backlog batches.")
    except Exception as e:
        logger.error(f"Failed to fetch backlog: {e}")


# ==============================================================================
# DATA PROCESSING
# ==============================================================================


def download_transcript(minio: Minio, transcript_key: str) -> Dict[str, Any]:
    """Streams a JSON transcript from the silver MinIO bucket and parses it."""
    logger.info(f"Downloading transcript: {transcript_key}")
    response = minio.get_object("silver", transcript_key)
    try:
        raw = b"".join(response.stream(32 * 1024))
        return json.loads(raw.decode("utf-8"))
    finally:
        response.close()
        response.release_conn()


def section_transcript(
    whisper_segments: List[Dict[str, Any]],
    target_duration_s: int = SECTION_TARGET_DURATION_S,
) -> List[List[Dict[str, Any]]]:
    """
    Groups whisper segments into variable-length sections.

    Each whisper segment is a sentence-level unit (text + start/end + words).
    Segments are accumulated until the section's wall-clock span reaches
    `target_duration_s`; the cut always lands at a segment boundary so no
    sentence is ever split across two sections.

    ── Swap this function for topic-based splitting ──────────────────────────
    Alternative strategies that fit the same return type:
      • Embedding cosine-shift: compute sentence embeddings, detect valleys in
        inter-sentence similarity (requires sentence-transformers).
      • TextTiling: lexical cohesion on sliding token windows (nltk.tokenize).
      • LLM chapter detection: batch segment texts to a structured-output call.
    All alternatives should return List[List[Dict]] with the same segment keys.
    ─────────────────────────────────────────────────────────────────────────

    Args:
        whisper_segments: Output of faster-whisper; each dict must contain
                          at least {"start": float, "end": float, "text": str}.
        target_duration_s: Soft cap on section length in seconds.

    Returns:
        Ordered list of sections; each section is an ordered list of whisper
        segment dicts (the original dicts, not copies).
    """
    if not whisper_segments:
        return []

    sections: List[List[Dict[str, Any]]] = []
    current: List[Dict[str, Any]] = []
    section_start: Optional[float] = None

    for seg in whisper_segments:
        if section_start is None:
            section_start = seg["start"]

        current.append(seg)

        if (seg["end"] - section_start) >= target_duration_s:
            sections.append(current)
            current = []
            section_start = None  # reset; next segment will anchor the new section

    if current:
        sections.append(current)

    return sections


async def store_sections(
    episode_id: str,
    batch_id: str,
    sections: List[List[Dict[str, Any]]],
    store: Store,
) -> int:
    """
    Persists sections and transcript lines to the database.

    Mapping:
      section  (N whisper segments)  →  one `segments` row
      segment  (one whisper segment) →  one `transcript_lines` row

    Both inserts are idempotent via ON CONFLICT DO UPDATE, so the episode can
    be re-processed safely if the batch is retried.

    Returns:
        Total number of transcript_lines rows written.
    """
    total_lines = 0

    for section_idx, section in enumerate(sections):
        if not section:
            continue

        start_s = int(round(section[0]["start"]))
        end_s = int(round(section[-1]["end"]))
        section_text = " ".join(s["text"].strip() for s in section)

        # Each section is committed in its own transaction so a single bad
        # section doesn't roll back an otherwise-complete episode.
        async with store.pool.acquire() as conn:
            async with conn.transaction():
                segment_id: str = await conn.fetchval(
                    """
                    INSERT INTO segments
                        (episode_id, batch_id, segment_idx, start_time, end_time, transcript)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (episode_id, segment_idx) DO UPDATE
                        SET transcript = EXCLUDED.transcript,
                            start_time = EXCLUDED.start_time,
                            end_time   = EXCLUDED.end_time,
                            batch_id   = EXCLUDED.batch_id
                    RETURNING id
                    """,
                    episode_id,
                    batch_id,
                    section_idx,
                    start_s,
                    end_s,
                    section_text,
                )

                # Build records for executemany – one row per whisper segment.
                line_records = [
                    (
                        str(segment_id),
                        batch_id,
                        line_idx,
                        int(round(line["start"])),
                        int(round(line["end"])),
                        line["text"].strip(),
                    )
                    for line_idx, line in enumerate(section)
                ]

                await conn.executemany(
                    """
                    INSERT INTO transcript_lines
                        (segment_id, batch_id, line_idx, start_time, end_time, text)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (segment_id, line_idx) DO UPDATE
                        SET text       = EXCLUDED.text,
                            start_time = EXCLUDED.start_time,
                            end_time   = EXCLUDED.end_time,
                            batch_id   = EXCLUDED.batch_id
                    """,
                    line_records,
                )

        total_lines += len(section)
        logger.debug(
            f"  Section {section_idx}: {start_s}s–{end_s}s "
            f"({len(section)} lines, segment_id={segment_id})"
        )

    return total_lines


async def process_episode(
    episode_id: str,
    batch_id: str,
    store: Store,
    minio: Minio,
) -> None:
    """
    End-to-end processing for one episode:
      1. Resolve transcript_key from the database.
      2. Download the Whisper JSON from MinIO silver.
      3. Section the transcript into chapter-sized groups.
      4. Persist segments + transcript_lines to Postgres.
    """
    transcript_key: Optional[str] = await store.pool.fetchval(
        "SELECT transcript_key FROM episodes WHERE id = $1", episode_id
    )
    if not transcript_key:
        raise ValueError(
            f"Episode {episode_id} has no transcript_key — "
            "transcription may not have completed successfully."
        )

    # Blocking MinIO + JSON parse → offloaded so the event loop stays responsive
    transcript = await asyncio.to_thread(download_transcript, minio, transcript_key)
    whisper_segments: List[Dict[str, Any]] = transcript.get("segments", [])

    if not whisper_segments:
        logger.warning(
            f"Episode {episode_id}: transcript contains no segments. Skipping."
        )
        return

    sections = section_transcript(whisper_segments, SECTION_TARGET_DURATION_S)
    total_lines = await store_sections(episode_id, batch_id, sections, store)

    logger.info(
        f"Episode {episode_id}: "
        f"{len(sections)} sections, {total_lines} transcript lines."
    )


# ==============================================================================
# WORKLOAD ORCHESTRATION
# ==============================================================================


async def claim_and_process_batch(
    transcription_batch_id: str,
    store: Store,
    minio: Minio,
) -> None:
    logger.info(
        f"Processing workload from Transcription Batch: {transcription_batch_id}"
    )

    segmenting_batch_id = await store.create_pipeline_batch("segmenting", "full")

    # Atomically claims episodes and marks the transcription batch as 'consumed'.
    episode_ids = await store.claim_batch_episodes(
        transcription_batch_id, segmenting_batch_id
    )

    if not episode_ids:
        logger.info(
            f"Workload {transcription_batch_id} already claimed or empty. "
            "Discarding segmenting batch."
        )
        await store.pool.execute(
            "DELETE FROM pipeline_batches WHERE id = $1", segmenting_batch_id
        )
        return

    logger.info(
        f"Claimed {len(episode_ids)} episodes → Segmenting Batch {segmenting_batch_id}"
    )

    for episode_id in episode_ids:
        try:
            await process_episode(episode_id, segmenting_batch_id, store, minio)
        except Exception as e:
            logger.error(f"Failed to segment episode {episode_id}: {e}", exc_info=True)

    await store.complete_pipeline_batch(
        batch_id=segmenting_batch_id,
        status="success",
        notify_channel="processing_ready",
    )


# ==============================================================================
# ENTRYPOINT
# ==============================================================================


async def main() -> None:
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_exit_signals)

    pg_url = os.getenv("POSTGRES_URL", "postgresql://user:pass@localhost:5432/db")
    store = Store(pg_url)
    await store.connect()

    minio = init_minio_client()

    listener = asyncio.create_task(postgres_listener_task(pg_url))
    await queue_backlog_batches(store)

    logger.info("Worker ready.")

    while not shutdown_event.is_set():
        try:
            try:
                transcription_batch_id = await asyncio.wait_for(
                    internal_task_queue.get(), timeout=1.0
                )
            except asyncio.TimeoutError:
                continue

            await claim_and_process_batch(transcription_batch_id, store, minio)
            internal_task_queue.task_done()

        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Unhandled error during batch: {e}", exc_info=True)
            await asyncio.sleep(2)

    logger.info("Cleaning up...")
    listener.cancel()
    await store.close()
    logger.info("Worker stopped.")


if __name__ == "__main__":
    asyncio.run(main())
