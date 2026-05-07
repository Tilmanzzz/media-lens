from __future__ import annotations

import argparse
import json
import uuid
from pathlib import Path
from typing import Any, Dict, List

from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    PointStruct,
    VectorParams,
)

COLLECTION_NAME = "podcast_embeddings"
VECTOR_SIZE = 384


def deterministic_id(episode_id: str, chunk_id: str, level: str) -> str:
    seed = f"{episode_id}|{chunk_id}|{level}"
    return str(uuid.uuid5(uuid.NAMESPACE_URL, seed))


def ensure_collection(client: QdrantClient) -> None:
    collections = [c.name for c in client.get_collections().collections]
    if COLLECTION_NAME not in collections:
        client.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=VectorParams(size=VECTOR_SIZE, distance=Distance.COSINE),
        )
        print(f"Created collection '{COLLECTION_NAME}'")


def build_points(records: List[Dict[str, Any]], level: str) -> List[PointStruct]:
    points = []
    for record in records:
        embedding = record.get("embedding")
        if not embedding or len(embedding) != VECTOR_SIZE:
            continue

        episode_id = str(record.get("episode_id", ""))
        chunk_id = str(record.get("chunk_id", record.get("segment_id", "")))

        point_id = deterministic_id(episode_id, chunk_id, level)

        payload = {
            "episode_id": episode_id,
            "episode_title": str(record.get("episode_title", "")),
            "podcast_name": str(record.get("podcast_title", "")),
            "podcast_id": str(record.get("podcast_id", "")),
            "cover_path": str(record.get("cover_path", "")),
            "text": str(record.get("transcription", "")),
            "start_time": int(record.get("start_time", 0)),
            "embedding_level": level,
        }

        points.append(PointStruct(id=point_id, vector=embedding, payload=payload))

    return points


def upsert_embeddings(client: QdrantClient, input_path: Path, batch_size: int = 100) -> int:
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

        points = build_points(records, level)

        for i in range(0, len(points), batch_size):
            batch = points[i : i + batch_size]
            client.upsert(collection_name=COLLECTION_NAME, points=batch)
            total_upserted += len(batch)

        print(f"  {level}: {len(points)} points upserted")

    return total_upserted


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write transcript embeddings to Qdrant.")
    parser.add_argument("--input", required=True, help="Path to embedded output JSON from transcript_embedder")
    parser.add_argument("--qdrant-url", default="http://localhost:6333", help="Qdrant server URL")
    parser.add_argument("--batch-size", type=int, default=100, help="Upsert batch size")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    input_path = Path(args.input).expanduser().resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    client = QdrantClient(url=args.qdrant_url)
    ensure_collection(client)

    total = upsert_embeddings(client, input_path, batch_size=args.batch_size)
    print(f"Done. Total points upserted: {total}")


if __name__ == "__main__":
    main()
