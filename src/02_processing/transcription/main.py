import os
import sys
import json
import asyncio
import logging
import signal
import tempfile
from minio import Minio
from faster_whisper import WhisperModel

# Inject parent directory path for clean internal imports
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from internal.python.queue.redis import QueueClient
from internal.python.db.store import Store
from internal.python.db.models import TranscriptSegment, Word

# Setup standard structured logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("transcription_worker")

shutdown_event = asyncio.Event()


def handle_exit_signals():
    logger.info("Received termination signal. Initiating graceful shutdown...")
    shutdown_event.set()


async def process_episode(
    episode_id: str,
    store: Store,
    minio_bronze: Minio,
    minio_silver: Minio,
    model: WhisperModel,
) -> None:
    """Core audio transcription data processing pipeline."""
    # 1. Fetch metadata from Postgres
    ep = await store.get_episode_by_id(episode_id)
    if not ep:
        raise ValueError(f"Episode metadata not found in database for ID: {episode_id}")

    # 2. Download raw audio from bronze MinIO bucket to a secure temp file
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=True) as tmp_file:
        logger.info(f"Downloading audio from bronze: {ep.audio_key}")
        response = minio_bronze.get_object("bronze", ep.audio_key)
        try:
            for chunk in response.stream(32 * 1024):
                tmp_file.write(chunk)
            tmp_file.flush()
        finally:
            response.close()
            response.release_conn()

        # 3. Compute Native Speech-to-Text via faster-whisper
        logger.info(f"Starting compute engine for: {ep.title}")
        segments, _ = model.transcribe(
            tmp_file.name, word_timestamps=True, vad_filter=True
        )

        raw_output = {"text": "", "segments": []}
        parsed_segments: list[TranscriptSegment] = []
        full_text_accumulator = []

        for segment in segments:
            words_list = []
            if segment.words:
                for w in segment.words:
                    words_list.append(
                        Word(
                            word=w.word.strip(),
                            start=w.start,
                            end=w.end,
                            probability=w.probability,
                        )
                    )

            parsed_seg = TranscriptSegment(
                start=segment.start,
                end=segment.end,
                text=segment.text.strip(),
                words=words_list if words_list else None,
            )
            parsed_segments.append(parsed_seg)
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

    # 4. Export immutable raw JSON asset to MinIO silver bucket
    transcript_key = f"{ep.audio_key}.json"
    raw_json_bytes = json.dumps(raw_output).encode("utf-8")

    with tempfile.NamedTemporaryFile(delete=True) as tmp_json:
        tmp_json.write(raw_json_bytes)
        tmp_json.flush()
        tmp_json.seek(0)

        logger.info(
            f"Uploading raw transcript tracking asset to silver: {transcript_key}"
        )
        minio_silver.put_object(
            bucket_name="silver",
            object_name=transcript_key,
            data=tmp_json,
            length=len(raw_json_bytes),
            content_type="application/json",
        )

    # 5. Persist structural data points into PostgreSQL
    logger.info(
        f"Persisting {len(parsed_segments)} transcript segments into operational database."
    )
    await store.insert_transcript_segments(ep.id, parsed_segments)
    await store.set_transcript_key(ep.id, transcript_key)
    await store.mark_pending_sectioning(ep.id)


async def main():
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_exit_signals)

    # Initialize external shared connections ONCE
    q = QueueClient(os.getenv("REDIS_ADDR", "localhost:6379"))
    store = Store(os.getenv("POSTGRES_URL", ""))

    await q.initialize()
    await store.connect()

    # Configure MinIO Object Layer Abstractions
    minio_endpoint = (
        os.getenv("MINIO_ENDPOINT", "localhost:9000")
        .replace("http://", "")
        .replace("https://", "")
    )
    minio_user = os.getenv("MINIO_USER", "minioadmin")
    minio_pass = os.getenv("MINIO_PASS", "minioadmin")

    minio_bronze = Minio(
        minio_endpoint, access_key=minio_user, secret_key=minio_pass, secure=False
    )
    minio_silver = Minio(
        minio_endpoint, access_key=minio_user, secret_key=minio_pass, secure=False
    )

    # Contextual check to safely select execution device bounds
    device = "cuda" if os.getenv("USE_CUDA", "false").lower() == "true" else "cpu"
    compute_type = "float16" if device == "cuda" else "int8"

    logger.info(
        f"Loading faster-whisper engine using [{device}] with compute type [{compute_type}]..."
    )
    model = WhisperModel("large-v3", device=device, compute_type=compute_type)

    consumer_id = os.getenv("HOSTNAME", "fallback-worker")
    logger.info(f"Transcription worker running. Identification tag: [{consumer_id}]")

    while not shutdown_event.is_set():
        try:
            # Priority Step A: Claim stale unacknowledged pending tasks hanging in PEL
            message_id, episode_id = await q.claim_stale_transcription(consumer_id)

            # Priority Step B: If PEL is clear, block-wait for a fresh task
            if not message_id:
                message_id, episode_id = await q.dequeue_transcription(consumer_id)

            if not message_id:
                # No data returned during loop block window
                await asyncio.sleep(0.1)
                continue

            if message_id and not episode_id:
                logger.error(
                    f"Payload Error: Message ID {message_id} pulled from stream, but field 'episode_id' "
                    "is missing or empty. Acknowledging message to prevent poison pill loop."
                )
                await q.ack_transcription(message_id)
                continue

            logger.info(
                f"Task acquired. Processing Episode ID: {episode_id} (Message ID: {message_id})"
            )

            # Execute processing pipeline
            await process_episode(episode_id, store, minio_bronze, minio_silver, model)

            # Advance to next stream and acknowledge current completion
            await q.enqueue_sectioning(episode_id)
            await q.ack_transcription(message_id)
            logger.info(f"Successfully processed and acknowledged task: {message_id}")

        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(
                f"Execution error occurred inside core task processing cycle: {e}",
                exc_info=True,
            )

            # Recovery attempt for missing consumer group configurations
            if "NOGROUP" in str(e):
                logger.info(
                    "Detected missing consumer group. Attempting to recover state..."
                )
                try:
                    await q.initialize()
                except Exception as recovery_err:
                    logger.error(f"State recovery failed: {recovery_err}")

            await asyncio.sleep(2)

    # Resource Cleanup Phase
    logger.info("Cleaning resources up...")
    await q.close()
    await store.close()
    logger.info("Worker gracefully stopped.")


if __name__ == "__main__":
    asyncio.run(main())
