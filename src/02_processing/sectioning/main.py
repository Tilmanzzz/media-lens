import os
import sys
import json
import asyncio
import logging
import signal
import asyncpg
import torch
from typing import Any, Dict, List, Optional
from minio import Minio
from nltk.tokenize import TextTilingTokenizer
from transformers import PegasusForConditionalGeneration, PegasusTokenizer, pipeline

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from internal.python.db.store import Store

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("segmenting_worker")

shutdown_event = asyncio.Event()
internal_task_queue: asyncio.Queue[str] = asyncio.Queue()

# Global variables for local NLP pipelines
pegasus_model = None
pegasus_tokenizer = None
classifier_pipeline = None  # Pre-defined candidate labels for the zero-shot classifier to enforce one-word descriptive titles
CANDIDATE_TOPICS = [
    # --- Geopolitics, Defense & Nations ---
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
    # --- Technology & Digital Infrastructure ---
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
    # --- Economics, Finance & Business ---
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
    # --- Politics, Law & Governance ---
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
    # --- Science, Nature & Environment ---
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
    # --- History & Society ---
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
    # --- Health, Medicine & Fitness ---
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
    # --- Culture, Arts & Media ---
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
    # --- Lifestyle, Leisure & Community ---
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
    # --- Religion, Beliefs & Alternative ---
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
    # --- Catch-All & Meta ---
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


# ==============================================================================
# LOCAL NLP MODELS PIPELINE (PEGASUS SETUP)
# ==============================================================================


def init_local_nlp_models():
    """Initializes PEGASUS abstraction engine and zero-shot classifier on GPU/CPU."""
    global pegasus_model, pegasus_tokenizer, classifier_pipeline
    device_idx = 0 if torch.cuda.is_available() else -1
    device_str = "cuda" if device_idx == 0 else "cpu"
    logger.info(f"Initializing local NLP pipelines on device: {device_str.upper()}")

    # Load explicit Pegasus model & tokenizer pairs
    model_name = "google/pegasus-cnn_dailymail"  # Alternative: "google/pegasus-xsum" for shorter summaries
    pegasus_tokenizer = PegasusTokenizer.from_pretrained(model_name)
    pegasus_model = PegasusForConditionalGeneration.from_pretrained(model_name).to(
        device_str
    )

    # Zero-shot Classifier for exact one-word category filtering (~500 MB)
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


def process_metadata_locally(text: str) -> tuple[str, str]:
    """Runs local inference using explicit Tokenizer layers to avoid prompt bleed."""
    global pegasus_model, pegasus_tokenizer, classifier_pipeline
    device_str = "cuda" if torch.cuda.is_available() else "cpu"

    try:
        # Explicit input tokenization with safety clipping down to Pegasus context limits (1024 tokens)
        inputs = pegasus_tokenizer(
            text, max_length=1024, truncation=True, return_tensors="pt"
        ).to(device_str)

        # Abstractive execution
        summary_ids = pegasus_model.generate(
            inputs["input_ids"],
            max_length=80,
            min_length=25,
            num_beams=4,
            length_penalty=2.0,
            early_stopping=True,
        )

        # Decode only target generated values
        summary = pegasus_tokenizer.decode(summary_ids[0], skip_special_tokens=True)
    except Exception as e:
        logger.error(f"Local PEGASUS summarization failed: {e}")
        summary = "Summary generation failed."

    # Assign exact One-Word Class Label via Zero-Shot Layer
    try:
        classifier_out = classifier_pipeline(
            text[:4000], candidate_labels=CANDIDATE_TOPICS, multi_label=False
        )
        title = classifier_out["labels"][0]
    except Exception as e:
        logger.error(f"Local zero-shot classification failed: {e}")
        title = "General"

    return title, summary


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

        # Execute heavy deep learning pipelines offloaded inside an isolation thread pool
        title, summary = await asyncio.to_thread(process_metadata_locally, section_text)

        async with store.pool.acquire() as conn:
            async with conn.transaction():
                segment_id: str = await conn.fetchval(
                    """
                    INSERT INTO segments
                        (episode_id, batch_id, segment_idx, start_time, end_time, title, summary, transcript)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    ON CONFLICT (episode_id, segment_idx) DO UPDATE
                        SET title      = EXCLUDED.title,
                            summary    = EXCLUDED.summary,
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
                    summary,
                    section_text,
                )

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
    return total_lines


async def process_episode(
    episode_id: str, batch_id: str, store: Store, minio: Minio
) -> None:
    transcript_key: Optional[str] = await store.pool.fetchval(
        "SELECT transcript_key FROM episodes WHERE id = $1", episode_id
    )
    if not transcript_key:
        raise ValueError(f"Episode {episode_id} has no transcript_key")

    transcript = await asyncio.to_thread(download_transcript, minio, transcript_key)
    whisper_segments: List[Dict[str, Any]] = transcript.get("segments", [])

    if not whisper_segments:
        logger.warning(f"Episode {episode_id}: empty segments. Skipping.")
        return

    sections = section_transcript_by_topic(whisper_segments)
    total_lines = await store_sections(episode_id, batch_id, sections, store)
    logger.info(f"Episode {episode_id}: {len(sections)} sections generated.")


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
    nltk.download("stopwords", quiet=True)  # Added missing resource
    asyncio.run(main())
