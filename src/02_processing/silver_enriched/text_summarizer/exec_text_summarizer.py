from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

from .text_summarizer_config import TextSummarizerConfig
from .text_summarizer_core import TextSummarizer


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


def apply_filters(chunks: List[Dict[str, Any]], episode_id: Any, chapter_id: Any) -> List[Dict[str, Any]]:
    filtered = chunks

    if episode_id is not None:
        filtered = [c for c in filtered if c.get("episode_id") == episode_id]

    if chapter_id is not None:
        filtered = [c for c in filtered if c.get("chapter_id") == chapter_id]

    return filtered


def print_episode_summaries(episode_summaries: List[Dict[str, Any]]) -> None:
    for summary in episode_summaries:
        print("\n--- EPISODE ---")
        print(f"Episode {summary['episode_id']} ({summary['episode_title']})")
        print(summary["summary"])


def print_chapter_summaries(chapter_summaries: List[Dict[str, Any]]) -> None:
    for summary in chapter_summaries:
        print("\n--- chapter ---")
        print(f"Episode {summary['episode_id']} ({summary['episode_title']}) | chapter {summary['chapter_id']}")
        print(summary["summary"])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize podcast episodes and chapters from transcript chunks.")

    parser.add_argument("--config", default="text_summarizer_config.json", help="Path to config JSON")
    parser.add_argument("--input", default=None, help="Path to chunks input JSON")
    parser.add_argument("--mode", choices=["episode", "chapter", "both"], default=None)

    parser.add_argument("--episode-id", type=int, default=None)
    parser.add_argument("--chapter-id", type=int, default=None)

    parser.add_argument("--output", default=None, help="Output JSON file path")

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    config = TextSummarizerConfig.from_file(args.config)
    summarizer = TextSummarizer(config=config)
    summarizer.logger.info("Starting text summarization run")

    input_path = args.input or config.default_input_path
    mode = args.mode or config.default_mode
    output_path = args.output or config.default_output_path

    chunks = load_chunks(input_path)
    filtered_chunks = apply_filters(chunks, args.episode_id, args.chapter_id)

    if not filtered_chunks:
        summarizer.logger.warning("No chunks matched the selected filters")
        print("No chunks matched the selected filters.")
        return

    output: Dict[str, Any] = {}

    if mode in {"episode", "both"}:
        episode_summaries = summarizer.summarize_all_episodes(filtered_chunks)
        output["episodes"] = episode_summaries
        print_episode_summaries(episode_summaries)

    if mode in {"chapter", "both"}:
        chapter_summaries = summarizer.summarize_all_chapters(filtered_chunks)
        output["chapters"] = chapter_summaries
        print_chapter_summaries(chapter_summaries)

    out_path = Path(output_path).expanduser()
    if not out_path.is_absolute():
        out_path = Path(__file__).resolve().parent / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    print(f"\nSaved output to: {out_path}")
    summarizer.logger.info("Saved output JSON to %s", out_path)

    summarizer.logger.info("Text summarization run finished")


if __name__ == "__main__":
    main()
