import os
import sys
import json
import asyncio
import logging
import signal
import asyncpg
import torch
from typing import Any, Dict, List
from minio import Minio
from nltk.tokenize import TextTilingTokenizer
from transformers import pipeline

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from internal.python.db.store import Store

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("segmenting_worker")

shutdown_event = asyncio.Event()
internal_task_queue: asyncio.Queue[str] = asyncio.Queue()

classifier_pipeline = None

CANDIDATE_TOPICS = [
    "Geopolitics",
    "Diplomacy",
    "Defense",
    "Military",
    "Warfare",
    "Espionage",
    "Europe",
    "Asia",
    "Americas",
    "Africa",
    "China",
    "Iran",
    "Russia",
    "Ukraine",
    "MidEast",
    "Balkans",
    "NATO",
    "Sovereignty",
    "Borders",
    "Sanctions",
    "Technology",
    "Software",
    "Hardware",
    "Internet",
    "AI",
    "Cybersecurity",
    "Robotics",
    "Crypto",
    "Blockchain",
    "Quantum",
    "Data",
    "Networking",
    "Automation",
    "Cloud",
    "OpenSource",
    "Programming",
    "Biotech",
    "Telecom",
    "Business",
    "Economy",
    "Finance",
    "Investing",
    "Trading",
    "Macroeconomics",
    "Stocks",
    "Commodities",
    "RealEstate",
    "Banking",
    "Inflation",
    "Taxation",
    "Startups",
    "Entrepreneurship",
    "Management",
    "Marketing",
    "Labor",
    "Logistics",
    "Politics",
    "Elections",
    "Government",
    "Law",
    "Constitution",
    "Judiciary",
    "Regulation",
    "Policy",
    "Corruption",
    "Democracy",
    "Activism",
    "Protest",
    "Science",
    "Physics",
    "Chemistry",
    "Biology",
    "Astronomy",
    "Space",
    "Environment",
    "Climate",
    "Energy",
    "Sustainability",
    "Geology",
    "Weather",
    "Ecology",
    "Nuclear",
    "Wildlife",
    "Oceans",
    "History",
    "Antiquity",
    "War",
    "Revolution",
    "Archaeology",
    "Anthropology",
    "Society",
    "Culture",
    "Philosophy",
    "Ethics",
    "Sociology",
    "Demographics",
    "Geography",
    "Documentary",
    "Biography",
    "TrueCrime",
    "Health",
    "Medicine",
    "Fitness",
    "Nutrition",
    "MentalHealth",
    "Psychology",
    "Neuroscience",
    "Anatomy",
    "Epidemiology",
    "Wellness",
    "Biohacking",
    "Longevity",
    "Arts",
    "Literature",
    "Books",
    "Poetry",
    "Design",
    "Architecture",
    "Music",
    "Cinema",
    "Film",
    "Television",
    "Gaming",
    "Theater",
    "Fashion",
    "Photography",
    "Language",
    "Linguistics",
    "Journalism",
    "Leisure",
    "Hobbies",
    "Sports",
    "Athletics",
    "Racing",
    "Automotive",
    "Aviation",
    "Travel",
    "Food",
    "Cooking",
    "Fermentation",
    "Agriculture",
    "Parenting",
    "Family",
    "Pets",
    "Animals",
    "Education",
    "Careers",
    "Religion",
    "Spirituality",
    "Theology",
    "Mythology",
    "Buddhism",
    "Christianity",
    "Hinduism",
    "Islam",
    "Judaism",
    "Esotericism",
    "Occult",
    "Astrology",
    "General",
    "Interview",
    "News",
    "Opinion",
    "Debate",
    "Analysis",
    "Review",
]


def handle_exit_signals() -> None:
    logger.info("Received termination signal. Shutting down...")
    shutdown_event.set()


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


def init_local_nlp_models():
    global classifier_pipeline
    device_idx = 0 if torch.cuda.is_available() else -1
    device_str = "cuda" if device_idx == 0 else "cpu"
    logger.info(f"Initializing local NLP pipelines on device: {device_str.upper()}")

    classifier_pipeline = pipeline(
        "zero-shot-classification",
        model="MoritzLaurer/DeBERTa-v3-base-mnli-fever-anli",
        device=device_idx,
    )


def download_transcript(minio: Minio, transcript_key: str) -> Dict[str, Any]:
    logger.info(f"Downloading transcript: {transcript_key}")
    response = minio.get_object("silver", transcript_key)
    try:
        raw = b"".join(response.stream(32 * 1024))
        return json.loads(raw.decode("utf-8"))
    finally:
        response.close()
        response.release_conn()


def section_transcript_by_topic(
    whisper_segments: List[Dict[str, Any]],
) -> List[List[Dict[str, Any]]]:
    if not whisper_segments:
        return []

    text_blocks = []
    block_buffer = []
    for i, seg in enumerate(whisper_segments):
        block_buffer.append(seg["text"].strip())
        if (i + 1) % 4 == 0:
            text_blocks.append(" ".join(block_buffer))
            block_buffer = []
    if block_buffer:
        text_blocks.append(" ".join(block_buffer))

    tiling_text = "\n\n".join(text_blocks)

    try:
        ttt = TextTilingTokenizer(w=20, k=10)
        tiles = ttt.tokenize(tiling_text)
    except Exception as e:
        logger.warning(f"TextTiling failed ({e}), falling back to single chapter.")
        return [whisper_segments]

    sections: List[List[Dict[str, Any]]] = []
    current_section: List[Dict[str, Any]] = []

    tile_idx = 0
    clean_tiles = [tile.replace("\n\n", " ").strip() for tile in tiles if tile.strip()]
    if not clean_tiles:
        return [whisper_segments]

    current_tile_text = clean_tiles[tile_idx]

    for seg in whisper_segments:
        current_section.append(seg)
        seg_text = seg["text"].strip()

        if seg_text in current_tile_text:
            current_tile_text = current_tile_text.replace(seg_text, "", 1)

        if not current_tile_text.strip() or len(current_tile_text) < 5:
            sections.append(current_section)
            current_section = []
            tile_idx += 1
            if tile_idx < len(clean_tiles):
                current_tile_text = clean_tiles[tile_idx]
            else:
                current_tile_text = ""

    if current_section:
        if sections:
            sections[-1].extend(current_section)
        else:
            sections.append(current_section)

    return sections


def process_metadata_locally(text: str) -> str:
    global classifier_pipeline

    try:
        classifier_out = classifier_pipeline(
            text[:4000], candidate_labels=CANDIDATE_TOPICS, multi_label=False
        )
        title = classifier_out["labels"][0]
    except Exception as e:
        logger.error(f"Local zero-shot classification failed: {e}")
        title = "General"

    return title


async def store_sections(
    episode_id: str,
    batch_id: str,
    sections: List[List[Dict[str, Any]]],
    store: Store,
) -> int:
    total_lines = 0

    for section_idx, section in enumerate(sections):
        if not section:
            continue

        start_s = int(round(section[0]["start"]))
        end_s = int(round(section[-1]["end"]))
        section_text = " ".join(s["text"].strip() for s in section)

        title = await asyncio.to_thread(process_metadata_locally, section_text)

        async with store.pool.acquire() as conn:
            async with conn.transaction():
                chapter_id: str = await conn.fetchval(
                    """
                    INSERT INTO chapters
                        (episode_id, batch_id, chapter_idx, start_time, end_time, title, transcript)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    ON CONFLICT (episode_id, chapter_idx) DO UPDATE
                        SET title      = EXCLUDED.title,
                            transcript = EXCLUDED.transcript,
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
                    title,
                    section_text,
                )

                line_records = [
                    (
                        str(chapter_id),
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
                        (chapter_id, batch_id, line_idx, start_time, end_time, text)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (chapter_id, line_idx) DO UPDATE
                        SET text       = EXCLUDED.text,
                            start_time = EXCLUDED.start_time,
                            end_time   = EXCLUDED.end_time,
                            batch_id   = EXCLUDED.batch_id
                    """,
                    line_records,
                )

        total_lines += len(section)
    return total_lines


async def process_episode(
    episode_id: str, batch_id: str, store: Store, minio: Minio
) -> None:
    # Fetch both transcript_key and podcast_id
    row = await store.pool.fetchrow(
        "SELECT transcript_key, podcast_id FROM episodes WHERE id = $1", episode_id
    )

    if not row or not row["transcript_key"]:
        raise ValueError(f"Episode {episode_id} has no transcript_key")

    transcript_key = row["transcript_key"]
    podcast_id = str(row["podcast_id"])

    transcript = await asyncio.to_thread(download_transcript, minio, transcript_key)
    whisper_segments: List[Dict[str, Any]] = transcript.get("segments", [])

    if not whisper_segments:
        logger.warning(f"Episode {episode_id}: empty segments. Skipping.")
        return

    sections = section_transcript_by_topic(whisper_segments)
    total_lines = await store_sections(episode_id, batch_id, sections, store)

    # Update both episode and podcast timestamps
    await store.set_preprocessing_updated_at(episode_id)
    await store.set_podcast_preprocessing_updated_at(podcast_id)

    logger.info(
        f"Episode {episode_id} (Podcast {podcast_id}): {len(sections)} sections generated."
    )


async def claim_and_process_batch(
    transcription_batch_id: str, store: Store, minio: Minio
) -> None:
    segmenting_batch_id = await store.create_pipeline_batch("segmenting", "full")
    episode_ids = await store.claim_batch_episodes(
        transcription_batch_id, segmenting_batch_id
    )

    if not episode_ids:
        await store.pool.execute(
            "DELETE FROM pipeline_batches WHERE id = $1", segmenting_batch_id
        )
        return

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


async def postgres_listener_task(pg_url: str) -> None:
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
                    logger.error(f"Payload error: {e}")

            await conn.add_listener("segmenting_ready", on_notification)
            while not shutdown_event.is_set():
                await asyncio.sleep(30)
                await conn.execute("SELECT 1")
        except Exception:
            if not shutdown_event.is_set():
                await asyncio.sleep(5)
        finally:
            if conn:
                await conn.close()


async def queue_backlog_batches(store: Store) -> None:
    try:
        rows = await store.pool.fetch(
            "SELECT id FROM pipeline_batches WHERE stage = 'transcription' AND status = 'success' ORDER BY start_ts ASC"
        )
        for row in rows:
            internal_task_queue.put_nowait(str(row["id"]))
    except Exception as e:
        logger.error(f"Backlog error: {e}")


async def main() -> None:
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_exit_signals)

    init_local_nlp_models()

    pg_url = os.getenv("POSTGRES_URL", "postgresql://user:pass@localhost:5432/db")
    store = Store(pg_url)
    await store.connect()
    minio = init_minio_client()

    listener = asyncio.create_task(postgres_listener_task(pg_url))
    await queue_backlog_batches(store)

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
        except Exception:
            await asyncio.sleep(2)

    listener.cancel()
    await store.close()


if __name__ == "__main__":
    import nltk

    nltk.download("punkt", quiet=True)
    nltk.download("stopwords", quiet=True)
    asyncio.run(main())
