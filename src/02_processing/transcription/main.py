import os
import io
import sys
import json
import asyncio
import logging
import signal
import tempfile
import asyncpg
from typing import Tuple
from minio import Minio
from faster_whisper import WhisperModel

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from internal.python.db.store import Store

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("transcription_worker")

shutdown_event = asyncio.Event()
internal_task_queue = asyncio.Queue()


def handle_exit_signals():
    logger.info("Received termination signal. Shutting down...")
    shutdown_event.set()


# ==============================================================================
# INFRASTRUCTURE & SETUP
# ==============================================================================


def init_minio_clients() -> Tuple[Minio, Minio]:
    minio_endpoint = (
        os.getenv("MINIO_ENDPOINT", "localhost:9000")
        .replace("http://", "")
        .replace("https://", "")
    )
    user = os.getenv("MINIO_USER", "minioadmin")
    password = os.getenv("MINIO_PASS", "minioadmin")

    # Both clients point to the same server, but we return two for logical separation
    bronze = Minio(minio_endpoint, access_key=user, secret_key=password, secure=False)
    silver = Minio(minio_endpoint, access_key=user, secret_key=password, secure=False)

    # Ensure required buckets exist before processing begins
    for bucket_name in ["bronze", "silver"]:
        if not bronze.bucket_exists(bucket_name):
            logger.info(f"Creating missing MinIO bucket: '{bucket_name}'")
            bronze.make_bucket(bucket_name)

    return bronze, silver


def init_whisper_model() -> WhisperModel:
    device = "cuda" if os.getenv("USE_CUDA", "false").lower() == "true" else "cpu"
    compute_type = "float16" if device == "cuda" else "int8"

    logger.info(f"Loading Whisper large-v3 ({device})")
    # available models:
    # # tiny, tiny.en, base, base.en, small, small.en, medium, medium.en, large-v1, large-v2, large-v3, large-v3-turbo, turbo, distil-small.en, distil-medium.en, distil-large-v2, distil-large-v3, distil-large-v3.5
    return WhisperModel("tiny", device=device, compute_type=compute_type)


async def postgres_listener_task(pg_url: str):
    """Listens for Postgres NOTIFY events with a heartbeat and auto-reconnect loop."""
    while not shutdown_event.is_set():
        conn = None
        try:
            conn = await asyncpg.connect(pg_url)

            def display_notification(connection, pid, channel, payload):
                try:
                    event_data = json.loads(payload)
                    if batch_id := event_data.get("batch_id"):
                        internal_task_queue.put_nowait(batch_id)
                except Exception as e:
                    logger.error(f"Failed parsing notification: {e}")

            await conn.add_listener("transcription_ready", display_notification)
            logger.info("Listening on 'transcription_ready'")

            # Heartbeat loop prevents silent Docker NAT network drops
            while not shutdown_event.is_set():
                await asyncio.sleep(30)
                await conn.execute("SELECT 1")  # Keep-alive ping

        except Exception as e:
            if not shutdown_event.is_set():
                logger.warning(
                    f"Database listener connection lost: {e}. Reconnecting in 5s..."
                )
                await asyncio.sleep(5)
        finally:
            if conn:
                try:
                    await conn.close()
                except Exception:
                    pass


async def queue_backlog_batches(store: Store):
    try:
        missed_batches = await store.pool.fetch(
            """
            SELECT id FROM pipeline_batches 
            WHERE stage = 'ingestion' AND status = 'success'
            ORDER BY start_ts ASC;
            """
        )
        for row in missed_batches:
            internal_task_queue.put_nowait(str(row["id"]))

        if missed_batches:
            logger.info(f"Queued {len(missed_batches)} backlog batches.")
    except Exception as e:
        logger.error(f"Failed to fetch backlog: {e}")


# ==============================================================================
# DATA PROCESSING
# ==============================================================================


def download_audio(minio_client: Minio, audio_key: str, target_file) -> None:
    logger.info(f"Downloading {audio_key}")
    response = minio_client.get_object("bronze", audio_key)
    try:
        for chunk in response.stream(32 * 1024):
            target_file.write(chunk)
        target_file.flush()
    finally:
        response.close()
        response.release_conn()


def upload_transcript(
    minio_client: Minio, transcript_key: str, raw_output: dict
) -> None:
    raw_json_bytes = json.dumps(raw_output).encode("utf-8")
    data_stream = io.BytesIO(raw_json_bytes)

    logger.info(f"Uploading raw transcript to {transcript_key}")
    minio_client.put_object(
        bucket_name="silver",
        object_name=transcript_key,
        data=data_stream,
        length=len(raw_json_bytes),
        content_type="application/json",
    )


async def process_episode(
    episode_id: str, store: Store, bronze: Minio, silver: Minio, model: WhisperModel
) -> None:
    ep = await store.get_episode_by_id(episode_id)
    if not ep:
        raise ValueError(f"Episode not found: {episode_id}")

    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=True) as tmp_file:
        download_audio(bronze, ep.audio_key, tmp_file)

        logger.info(f"Transcribing {ep.title}")

        # Capture the 'info' object instead of ignoring it with '_'
        whisper_segments, info = await asyncio.to_thread(
            model.transcribe, tmp_file.name, word_timestamps=True, vad_filter=True
        )

        raw_output = {
            "metadata": {
                "language": info.language,
                "language_probability": info.language_probability,
                "duration": info.duration,
            },
            "text": "",
            "segments": [],
        }
        full_text_accumulator = []

        for segment in whisper_segments:
            full_text_accumulator.append(segment.text)
            raw_output["segments"].append(
                {
                    "start": segment.start,
                    "end": segment.end,
                    "text": segment.text.strip(),
                    "words": [
                        {
                            "word": w.word.strip(),
                            "start": w.start,
                            "end": w.end,
                            "probability": w.probability,
                        }
                        for w in (segment.words or [])
                    ],
                }
            )

        raw_output["text"] = "".join(full_text_accumulator).strip()

    # Create a clean transcript path (e.g., audio/pid/guid/transcript.json)
    base_dir = os.path.dirname(ep.audio_key)
    transcript_key = f"{base_dir}/transcript.json"

    upload_transcript(silver, transcript_key, raw_output)

    logger.info(f"Updating database reference for {transcript_key}")
    await store.set_transcript_key(ep.id, transcript_key)


# ==============================================================================
# WORKLOAD ORCHESTRATION
# ==============================================================================


async def claim_and_process_batch(
    ingestion_batch_id: str,
    store: Store,
    bronze: Minio,
    silver: Minio,
    model: WhisperModel,
):
    logger.info(f"Processing workload from Ingestion Batch: {ingestion_batch_id}")

    transcription_batch_id = await store.create_pipeline_batch("transcription", "full")

    # Atomically claims episodes and marks the ingestion batch as 'consumed'.
    episode_ids = await store.claim_batch_episodes(
        ingestion_batch_id, transcription_batch_id
    )

    if not episode_ids:
        logger.info(
            f"Workload {ingestion_batch_id} claimed or empty. Discarding batch."
        )
        await store.pool.execute(
            "DELETE FROM pipeline_batches WHERE id = $1", transcription_batch_id
        )
        return

    logger.info(
        f"Claimed {len(episode_ids)} episodes for Transcription Batch: {transcription_batch_id}"
    )

    for episode_id in episode_ids:
        try:
            await process_episode(episode_id, store, bronze, silver, model)
        except Exception as e:
            logger.error(f"Failed processing episode {episode_id}: {e}")

    await store.complete_pipeline_batch(
        batch_id=transcription_batch_id,
        status="success",
        notify_channel="segmenting_ready",
    )


# ==============================================================================
# ENTRYPOINT
# ==============================================================================


async def main():
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_exit_signals)

    pg_url = os.getenv("POSTGRES_URL", "postgresql://user:pass@localhost:5432/db")
    store = Store(pg_url)
    await store.connect()

    minio_bronze, minio_silver = init_minio_clients()
    model = init_whisper_model()

    listener_task = asyncio.create_task(postgres_listener_task(pg_url))
    await queue_backlog_batches(store)

    logger.info("Worker ready.")

    while not shutdown_event.is_set():
        try:
            try:
                ingestion_batch_id = await asyncio.wait_for(
                    internal_task_queue.get(), timeout=1.0
                )
            except asyncio.TimeoutError:
                continue

            await claim_and_process_batch(
                ingestion_batch_id, store, minio_bronze, minio_silver, model
            )
            internal_task_queue.task_done()

        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"Error during batch processing: {e}", exc_info=True)
            await asyncio.sleep(2)

    logger.info("Cleaning up...")
    listener_task.cancel()
    await store.close()
    logger.info("Worker stopped.")


if __name__ == "__main__":
    asyncio.run(main())
