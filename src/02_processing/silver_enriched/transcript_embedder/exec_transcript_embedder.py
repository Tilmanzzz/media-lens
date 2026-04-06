from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List

from transcript_embedder_config import TranscriptEmbedderConfig
from transcript_embedder_core import TranscriptEmbedder


def load_chunks(input_path: str | Path) -> List[Dict[str, Any]]:
    path = Path(input_path).expanduser()
    if not path.is_absolute():
        path = Path(__file__).resolve().parent / path

    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {path}")

    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    if isinstance(data, list):
        return data

    if isinstance(data, dict) and isinstance(data.get("chunks"), list):
        return data["chunks"]

    raise ValueError("Input JSON must be a list of chunks or an object with a 'chunks' list.")


def apply_filters(chunks: List[Dict[str, Any]], podcast_id: Any, episode_id: Any, segment_id: Any) -> List[Dict[str, Any]]:
    filtered = chunks

    if podcast_id is not None:
        target = str(podcast_id)
        filtered = [chunk for chunk in filtered if str(chunk.get("podcast_id")) == target]

    if episode_id is not None:
        target = str(episode_id)
        filtered = [chunk for chunk in filtered if str(chunk.get("episode_id")) == target]

    if segment_id is not None:
        target = str(segment_id)
        filtered = [chunk for chunk in filtered if str(chunk.get("segment_id")) == target]

    return filtered


def build_output(embedder: TranscriptEmbedder, chunks: List[Dict[str, Any]], mode: str) -> Dict[str, Any]:
    output: Dict[str, Any] = {"embedded": {}}

    if mode in {"chunk", "all"}:
        output["embedded"]["chunk_level"] = embedder.embed_chunks(chunks)

    if mode in {"episode", "all"}:
        output["embedded"]["episode_level"] = embedder.embed_episodes(chunks)

    if mode in {"segment", "all"}:
        output["embedded"]["segment_level"] = embedder.embed_segments(chunks)

    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create transcript embeddings for chunk, episode, and segment levels.")
    parser.add_argument("--config", default="transcript_embedder_config.json", help="Path to config JSON")
    parser.add_argument("--input", default=None, help="Path to input transcript chunks JSON")
    parser.add_argument("--mode", choices=["chunk", "episode", "segment", "all"], default=None)

    parser.add_argument("--podcast-id", default=None)
    parser.add_argument("--episode-id", default=None)
    parser.add_argument("--segment-id", default=None)

    parser.add_argument("--output", default=None, help="Output JSON file path")

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    config = TranscriptEmbedderConfig.from_file(args.config)
    embedder = TranscriptEmbedder(config=config)
    embedder.logger.info("Starting transcript embedding run")

    input_path = args.input or config.default_input_path
    mode = args.mode or config.default_mode
    output_path = args.output or config.default_output_path

    chunks = load_chunks(input_path)
    filtered_chunks = apply_filters(chunks, args.podcast_id, args.episode_id, args.segment_id)

    if not filtered_chunks:
        embedder.logger.warning("No chunks matched the selected filters")
        print("No chunks matched the selected filters.")
        return

    output = build_output(embedder, filtered_chunks, mode)

    out_path = Path(output_path).expanduser()
    if not out_path.is_absolute():
        out_path = Path(__file__).resolve().parent / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"Saved output to: {out_path}")
    embedder.logger.info("Saved embedded output JSON to %s", out_path)
    embedder.logger.info("Transcript embedding run finished")


if __name__ == "__main__":
    main()
