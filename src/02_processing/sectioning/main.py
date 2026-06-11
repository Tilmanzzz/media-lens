import os
import sys
import json
import asyncio
import logging
import signal
from collections import defaultdict
from typing import Any, Dict, List

import asyncpg
import torch
from minio import Minio
from nltk.tokenize import TextTilingTokenizer
from transformers import pipeline

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from internal.python.db.store import Store

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("sectioning_worker")

shutdown_event = asyncio.Event()
internal_task_queue: asyncio.Queue[str] = asyncio.Queue()

classifier_pipeline = None

# Grouping labels hierarchically prevents the GPU from bottlenecking.
# A broad pass followed by a narrow pass cuts inference time significantly.
TOPIC_HIERARCHY = {
    "Geopolitics & Defense": [
        "Geopolitics",
        "Diplomacy",
        "Defense",
        "Military",
        "Warfare",
        "Espionage",
        "Sovereignty",
        "Borders",
        "Sanctions",
        "NATO",
    ],
    "Technology & Innovation": [
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
        "Telecom",
    ],
    "Business & Economy": [
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
    ],
    "Politics & Law": [
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
    ],
    "Science & Environment": [
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
    ],
    "History & Society": [
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
    ],
    "Health & Wellness": [
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
    ],
    "Arts & Entertainment": [
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
    ],
    "Lifestyle & Leisure": [
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
    ],
    "Education & Careers": ["Education", "Careers"],
    "Media & Format": [
        "General",
        "Interview",
        "News",
        "Opinion",
        "Debate",
        "Analysis",
        "Review",
        "Documentary",
        "Biography",
        "TrueCrime",
    ],
}


def handle_exit_signals() -> None:
    logger.info("Received termination signal. Shutting down...")
    shutdown_event.set()


def init_minio_client() -> Minio:
    # Deliberately leaving the raw endpoint here. If the env var includes 'http://'
    # when it shouldn't, we want it to fail loudly on startup rather than mask the issue.
    endpoint = os.getenv("MINIO_ENDPOINT", "localhost:9000")
    return Minio(
        endpoint,
        access_key=os.getenv("MINIO_USER", "minioadmin"),
        secret_key=os.getenv("MINIO_PASS", "minioadmin"),
        secure=False,
    )


def init_local_nlp_models():
    global classifier_pipeline

    # Fallback to CPU if CUDA isn't available (useful for local dev/testing without a GPU)
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
        # Buffer the stream to handle large podcast JSONs without causing a memory spike
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

    # TextTiling needs distinct paragraphs to analyze semantic shifts.
    # Grouping chunks of 4 segments guarantees enough context per "paragraph"
    # for the algorithm to find structural boundaries.
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
        # TextTiling can be fussy and throw errors if the text lacks variance or is too short.
        # We catch it so we don't drop the episode, falling back to a single chapter instead.
        logger.warning(f"TextTiling failed ({e}), falling back to single chapter.")
        return [whisper_segments]

    clean_tiles = [tile.replace("\n\n", " ").strip() for tile in tiles if tile.strip()]
    if not clean_tiles:
        return [whisper_segments]

    sections: List[List[Dict[str, Any]]] = []
    current_section: List[Dict[str, Any]] = []

    tile_idx = 0
    current_tile_target_len = len(clean_tiles[tile_idx])
    current_accumulated_len = 0

    # We use string length accumulation to map original Whisper segments back to the tiles.
    # Relying on `string.replace()` is too brittle because NLTK alters whitespace and punctuation.
    for seg in whisper_segments:
        seg_text = seg["text"].strip()
        current_section.append(seg)
        # +1 accounts for the space we add when joining the text later
        current_accumulated_len += len(seg_text) + 1

        # Allow a 15% length tolerance to account for NLTK's internal normalizations
        if current_accumulated_len >= current_tile_target_len * 0.85:
            sections.append(current_section)
            current_section = []
            tile_idx += 1
            if tile_idx < len(clean_tiles):
                current_tile_target_len = len(clean_tiles[tile_idx])
                current_accumulated_len = 0
            else:
                current_tile_target_len = float("inf")

    # Flush any remaining segments into the final section
    if current_section:
        if sections and tile_idx >= len(clean_tiles):
            sections[-1].extend(current_section)
        else:
            sections.append(current_section)

    return sections


def process_metadata_hierarchical(texts: List[str]) -> List[str]:
    global classifier_pipeline
    if not texts:
        return []

    # ---------------------------------------------------------
    # Note: No broad try/except block here. If the model OOMs
    # or fails a tensor operation, the container should crash
    # and restart rather than quietly labeling everything "General".
    # ---------------------------------------------------------

    # Phase 1: Figure out the broad category for every chunk in the batch
    broad_labels = list(TOPIC_HIERARCHY.keys())

    broad_results = classifier_pipeline(
        texts,
        candidate_labels=broad_labels,
        multi_label=False,
        truncation=True,  # Critical: Prevents crashes if a chunk exceeds 512 tokens
        max_length=512,
    )

    if isinstance(broad_results, dict):
        broad_results = [broad_results]

    # Group texts by their winning broad category so we can batch Phase 2 efficiently.
    category_to_indices = defaultdict(list)
    for i, res in enumerate(broad_results):
        category_to_indices[res["labels"][0]].append(i)

    final_labels = ["General"] * len(texts)

    # Phase 2: Narrow down the specific topic within the chosen broad category
    for broad_cat, indices in category_to_indices.items():
        # Inject "General" as a fallback in case the model is unsure about the subtopics
        narrow_labels = TOPIC_HIERARCHY[broad_cat] + ["General"]
        group_texts = [texts[i] for i in indices]

        narrow_results = classifier_pipeline(
            group_texts,
            candidate_labels=narrow_labels,
            multi_label=False,
            truncation=True,
            max_length=512,
        )

        if isinstance(narrow_results, dict):
            narrow_results = [narrow_results]

        # Map the detailed topics back to their original positions in the batch
        for idx, res in zip(indices, narrow_results):
            final_labels[idx] = res["labels"][0]

    return final_labels


async def process_episode(
    episode_id: str, batch_id: str, store: Store, minio: Minio
) -> None:
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
    sections = [s for s in sections if s]

    if not sections:
        return

    section_texts = [
        " ".join(s["text"].strip() for s in section) for section in sections
    ]

    # Process all metadata in a single call to maximize GPU utilization
    titles = await asyncio.to_thread(process_metadata_hierarchical, section_texts)

    total_lines = 0

    # Wrap all database inserts in a single transaction block.
    # Acquiring connections per-section creates massive network overhead.
    async with store.pool.acquire() as conn:
        async with conn.transaction():
            for section_idx, (section, title) in enumerate(zip(sections, titles)):
                start_s = int(round(section[0]["start"]))
                end_s = int(round(section[-1]["end"]))

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
                    section_texts[section_idx],
                )

                # Batch the transcript line inserts
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

    await store.set_preprocessing_updated_at(episode_id)
    await store.set_podcast_preprocessing_updated_at(podcast_id)

    logger.info(
        f"Episode {episode_id} (Podcast {podcast_id}): {len(sections)} sections generated ({total_lines} lines)."
    )


async def claim_and_process_batch(
    transcription_batch_id: str, store: Store, minio: Minio
) -> None:
    segmenting_batch_id = await store.create_pipeline_batch("segmenting", "full")
    episode_ids = await store.claim_batch_episodes(
        transcription_batch_id, segmenting_batch_id
    )

    if not episode_ids:
        # Cleanup the empty batch record so it doesn't clutter the DB
        await store.pool.execute(
            "DELETE FROM pipeline_batches WHERE id = $1", segmenting_batch_id
        )
        return

    for episode_id in episode_ids:
        # No sweeping try/except here. If DB operations or ML inferences crash,
        # let it bubble up so we can inspect the stack trace in the container logs.
        await process_episode(episode_id, segmenting_batch_id, store, minio)

    await store.complete_pipeline_batch(
        batch_id=segmenting_batch_id,
        status="success",
        notify_channel="processing_ready",
    )


async def postgres_listener_task(pg_url: str) -> None:
    # Keeps a dedicated connection open to listen for Postgres NOTIFY events
    while not shutdown_event.is_set():
        conn = await asyncpg.connect(pg_url)
        try:

            def on_notification(connection, pid, channel, payload):
                event = json.loads(payload)
                if batch_id := event.get("batch_id"):
                    internal_task_queue.put_nowait(batch_id)

            await conn.add_listener("segmenting_ready", on_notification)
            while not shutdown_event.is_set():
                await asyncio.sleep(30)
                # Ping the connection periodically to prevent silent disconnects
                await conn.execute("SELECT 1")
        finally:
            await conn.close()


async def queue_backlog_batches(store: Store) -> None:
    # On startup, fetch anything that finished transcription while this worker was offline.
    # No try/except; if Postgres is unreachable on boot, the container should exit.
    rows = await store.pool.fetch(
        "SELECT id FROM pipeline_batches WHERE stage = 'transcription' AND status = 'success' ORDER BY start_ts ASC"
    )
    for row in rows:
        internal_task_queue.put_nowait(str(row["id"]))


async def main() -> None:
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_exit_signals)

    init_local_nlp_models()

    pg_url = os.getenv("POSTGRES_URL")
    if not pg_url:
        raise ValueError("POSTGRES_URL environment variable is required")

    store = Store(pg_url)
    await store.connect()
    minio = init_minio_client()

    # Start the Postgres listener as a background task
    listener = asyncio.create_task(postgres_listener_task(pg_url))
    await queue_backlog_batches(store)

    while not shutdown_event.is_set():
        try:
            # Polling with a timeout allows the loop to regularly check the shutdown_event
            transcription_batch_id = await asyncio.wait_for(
                internal_task_queue.get(), timeout=1.0
            )
            await claim_and_process_batch(transcription_batch_id, store, minio)
            internal_task_queue.task_done()
        except asyncio.TimeoutError:
            continue
        except asyncio.CancelledError:
            break

    listener.cancel()
    await store.close()


if __name__ == "__main__":
    import nltk

    # Fetch both punkt and punkt_tab to ensure compatibility across different Python/NLTK versions
    nltk.download("punkt", quiet=True)
    nltk.download("punkt_tab", quiet=True)
    nltk.download("stopwords", quiet=True)
    asyncio.run(main())
