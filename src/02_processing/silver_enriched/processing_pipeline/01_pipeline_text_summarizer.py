from __future__ import annotations

import argparse
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional
import sys
from pathlib import Path

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src\\02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

from silver_enriched.text_summarizer.text_summarizer_config import TextSummarizerConfig
from silver_enriched.text_summarizer.text_summarizer_core import TextSummarizer

from common.db_connector import DbConnector
from silver_enriched.processing_pipeline.pipeline_utils import (
    LoadContext,
    expand_targets_from_chunks,
    fetch_chapter_ids_for_episode,
    fetch_chunks,
    fetch_delta_targets,
    should_include,
    should_include_between,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run text_summarizer against database sources (full or delta)."
    )
    parser.add_argument("--mode", choices=["full", "delta"], default="delta")
    parser.add_argument("--stage", default="processing", help="pipeline_batches.stage for watermark lookup")
    parser.add_argument("--watermark", default=None, help="ISO timestamp override for delta load")
    parser.add_argument("--batch-id", default=None, help="Batch UUID to store on writes")
    parser.add_argument("--testing", action="store_true", help="Enable test run parameters")
    parser.add_argument("--test-episode-id", type=str, default=None, help="Test run: episode id")
    parser.add_argument("--test-chapter-limit", type=int, default=3, help="Test run: max chapters")
    parser.add_argument(
        "--test-end-watermark",
        default=None,
        help="Test run: upper bound watermark (ISO timestamp)",
    )
    return parser.parse_args()

def update_episode_summaries(
    conn,
    summaries: Iterable[Dict[str, Any]],
    batch_id: Optional[str],
    processing_update_ts: Optional[datetime],
) -> int:

    if processing_update_ts is None:
        raise ValueError("processing_update_ts is required for processing writes")

    sql = (
        "UPDATE episodes SET summary = %s, processing_updated_at = %s, batch_id = %s "
        "WHERE id = %s"
    )

    updated = 0

    with conn.cursor() as cur:
        for summary in summaries:
            episode_id = summary.get("episode_id")
            text = summary.get("summary")

            if not episode_id or text is None:
                continue

            cur.execute(sql, (text, processing_update_ts, batch_id, episode_id))
            updated += cur.rowcount

    return updated


def update_chapter_summaries(
    conn,
    summaries: Iterable[Dict[str, Any]],
    batch_id: Optional[str],
    processing_update_ts: Optional[datetime],
) -> int:

    if processing_update_ts is None:
        raise ValueError("processing_update_ts is required for processing writes")

    sql = (
        "UPDATE chapter SET summary = %s, processing_updated_at = %s, batch_id = %s "
        "WHERE id = %s"
    )
    updated = 0

    with conn.cursor() as cur:
        for summary in summaries:
            chapter_id = summary.get("chapter_id")
            text = summary.get("summary")

            if not chapter_id or text is None:
                continue

            cur.execute(sql, (text, processing_update_ts, batch_id, chapter_id))
            updated += cur.rowcount

    return updated

def run_step(conn, ctx: LoadContext, args: argparse.Namespace) -> None:
    episode_ids = None
    chapter_ids = None

    if args.testing and args.test_end_watermark:
        episode_ids = None
        chapter_ids = None
    elif args.testing and args.test_episode_id:
        episode_ids = {str(args.test_episode_id)}
        chapter_ids = set(
            fetch_chapter_ids_for_episode(
                conn,
                str(args.test_episode_id),
                args.test_chapter_limit,
            )
        )
        if not chapter_ids:
            print("text_summarizer: No chapters found for test episode.")
            return

    if ctx.mode == "delta" and not (args.testing and args.test_episode_id):
        # use chapter-level processing_updated_at when checking watermark
        episode_ids, chapter_ids = fetch_delta_targets(conn, ctx, update_ts_level="chapter")
        if not episode_ids and not chapter_ids:
            print("text_summarizer: No delta changes detected.")
            return

    chunks = fetch_chunks(conn, episode_ids, chapter_ids, update_ts_level="chapter")
    if not chunks:
        print("text_summarizer: No chunks found.")
        return

    if ctx.mode == "delta" and not (args.testing and args.test_episode_id):
        end_ts = None
        if args.testing and args.test_end_watermark:
            end_ts = ctx.connector.parse_ts(args.test_end_watermark)
        delta_chunks: List[Dict[str, Any]] = []
        print("chunks count: ", len(chunks))
        for chunk in chunks:
            print(f"chunk: {chunk.get('chapter_id')} source_update_ts: {chunk.get('source_update_ts').isoformat() if chunk.get('source_update_ts') else 'None'}")
            ts = ctx.connector.parse_ts(chunk.get("source_update_ts"))
            if args.testing and end_ts is not None:
                include = should_include_between(ts, ctx.watermark, end_ts)
            else:
                include = should_include(ts, ctx)
            if include:
                delta_chunks.append(chunk)

        if not delta_chunks:
            print("text_summarizer: No chunks matched delta filter.")
            return

        episode_ids, chapter_ids = expand_targets_from_chunks(delta_chunks)
        chunks = fetch_chunks(conn, episode_ids, chapter_ids, update_ts_level="chapter")

    summarizer = TextSummarizer()
    print(summarizer.config)

    episode_summaries = summarizer.summarize_all_episodes(chunks)
    chapter_summaries = summarizer.summarize_all_chapters(chunks)

    total_updates = 0
    total_updates += update_episode_summaries(
        conn,
        episode_summaries,
        args.batch_id,
        ctx.processing_update_ts,
    )
    total_updates += update_chapter_summaries(
        conn,
        chapter_summaries,
        args.batch_id,
        ctx.processing_update_ts,
    )
    conn.commit()
    print(f"text_summarizer: Done. Rows updated: {total_updates}")


def main() -> None:
    args = parse_args()
    connector = DbConnector()

    with connector.get_connection() as conn:
        watermark = connector.parse_ts(args.watermark)
        if args.mode == "delta":
            if watermark is None:
                watermark = connector.get_watermark(conn, args.stage)
        print(watermark)
        ctx = LoadContext(
            mode=args.mode,
            watermark=watermark,
            connector=connector,
        )

        run_step(conn, ctx, args)


if __name__ == "__main__":
    main()
