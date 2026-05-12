from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Dict, List

import psycopg

VECTOR_SIZE = 384

INSERT_SQL = """
INSERT INTO embeddings (episode_id, chunk_id, embedding_level, embedding, text, start_time, episode_title, podcast_name, podcast_id, cover_path)
VALUES (%(episode_id)s, %(chunk_id)s, %(embedding_level)s, %(embedding)s::vector, %(text)s, %(start_time)s, %(episode_title)s, %(podcast_name)s, %(podcast_id)s, %(cover_path)s)
ON CONFLICT (episode_id, chunk_id, embedding_level)
DO UPDATE SET embedding = EXCLUDED.embedding, text = EXCLUDED.text, start_time = EXCLUDED.start_time,
             episode_title = EXCLUDED.episode_title, podcast_name = EXCLUDED.podcast_name,
             podcast_id = EXCLUDED.podcast_id, cover_path = EXCLUDED.cover_path
"""


def build_rows(records: List[Dict[str, Any]], level: str) -> List[Dict[str, Any]]:
    rows = []
    for record in records:
        embedding = record.get("embedding")
        if not embedding or len(embedding) != VECTOR_SIZE:
            continue

        episode_id = str(record.get("episode_id", ""))
        chunk_id = str(record.get("chunk_id", record.get("segment_id", "")))

        rows.append({
            "episode_id": episode_id,
            "chunk_id": chunk_id,
            "embedding_level": level,
            "embedding": str(embedding),
            "text": str(record.get("transcription", "")),
            "start_time": int(record.get("start_time", 0)),
            "episode_title": str(record.get("episode_title", "")),
            "podcast_name": str(record.get("podcast_title", "")),
            "podcast_id": str(record.get("podcast_id", "")),
            "cover_path": str(record.get("cover_path", "")),
        })

    return rows


def upsert_embeddings(conn: psycopg.Connection, input_path: Path, batch_size: int = 100) -> int:
    with input_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    embedded = data.get("embedded", data)

    total_upserted = 0

    level_map = {
        "chunk_level": "chunk",
        "segment_level": "segment",
        "episode_level": "episode",
        "podcast_level": "podcast",
    }

    for key, level in level_map.items():
        records = embedded.get(key, [])
        if not records:
            continue

        rows = build_rows(records, level)

        with conn.cursor() as cur:
            for i in range(0, len(rows), batch_size):
                batch = rows[i : i + batch_size]
                cur.executemany(INSERT_SQL, batch)
                total_upserted += len(batch)

        conn.commit()
        print(f"  {level}: {len(rows)} rows inserted")

    return total_upserted


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write transcript embeddings to PostgreSQL via pgvector.")
    parser.add_argument("--input", required=True, help="Path to embedded output JSON from transcript_embedder")
    parser.add_argument("--postgres-url", default=None, help="PostgreSQL connection URL (default: POSTGRES_URL env var)")
    parser.add_argument("--batch-size", type=int, default=100, help="Insert batch size")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    input_path = Path(args.input).expanduser().resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    postgres_url = args.postgres_url or os.environ.get("POSTGRES_URL")
    if not postgres_url:
        raise RuntimeError("POSTGRES_URL is not set")

    with psycopg.connect(postgres_url) as conn:
        total = upsert_embeddings(conn, input_path, batch_size=args.batch_size)

    print(f"Done. Total rows inserted: {total}")


if __name__ == "__main__":
    main()
