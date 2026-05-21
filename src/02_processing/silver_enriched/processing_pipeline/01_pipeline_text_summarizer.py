from __future__ import annotations

import argparse
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional
import sys
from pathlib import Path

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src\\02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

from silver_enriched.text_summarizer.text_summarizer_core import TextSummarizer

from common.db_connector import DbConnector
from common.app_logger import AppLogger
from silver_enriched.processing_pipeline.pipeline_utils import (
    LoadContext,
    build_pipeline_logger,
    fetch_chapter_ids_for_episode,
    fetch_chunks,
    load_json_config,
)


def parse_args() -> argparse.Namespace:
    pre_parser = argparse.ArgumentParser(add_help=False)
    pre_parser.add_argument("--config", default=None, help="Path to pipeline args JSON config")
    pre_args, remaining = pre_parser.parse_known_args()

    parser = argparse.ArgumentParser(
        description="Run text_summarizer against database sources (full or delta)."
    )
    parser.add_argument("--config", default="processing_pipeline_config.json", help="Path to pipeline args JSON config")
    parser.add_argument("--mode", choices=["full", "delta"], default="delta")
    parser.add_argument("--stage", default="processing", help="pipeline_batches.stage for watermark lookup")
    parser.add_argument("--watermark", default=None, help="ISO timestamp override for delta load")
    parser.add_argument("--batch-id", default=None, help="Batch UUID to store on writes")
    parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Run without database writes",
    )
    parser.add_argument("--testing", action="store_true", help="Enable test run parameters")
    parser.add_argument("--test-episode-id", type=str, default=None, help="Test run: episode id")
    parser.add_argument("--test-chapter-limit", type=int, default=3, help="Test run: max chapters")
    parser.add_argument(
        "--test-end-watermark",
        default=None,
        help="Test run: upper bound watermark (ISO timestamp)",
    )
    parser.add_argument(
        "--log-enabled",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Enable pipeline logging",
    )
    parser.add_argument("--log-level", default="INFO", help="Pipeline logger level")
    parser.add_argument("--log-dir", default=None, help="Optional pipeline log directory")
    parser.add_argument("--log-file", default="text_summarizer_pipeline.log", help="Pipeline log file name")

    config = load_json_config(pre_args.config or parser.get_default("config"), base_dir=Path(__file__).resolve().parent)
    if config:
        parser.set_defaults(**config)

    return parser.parse_args(remaining)

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
    logger = ctx.logger or build_pipeline_logger(
        module_name="text_summarizer_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    )

    chapter_ids = None
    end_ts = None

    if args.testing and args.test_end_watermark:
        end_ts = ctx.connector.parse_ts(args.test_end_watermark)

    if args.testing and args.test_episode_id:
        chapter_ids = set(
            fetch_chapter_ids_for_episode(
                conn,
                str(args.test_episode_id),
                args.test_chapter_limit,
            )
        )
        if not chapter_ids:
            logger.warning("text_summarizer: No chapters found for test episode.")
            return

    chunks = fetch_chunks(
        conn,
        step="text_summarizer",
        level="chapter",
        ids=chapter_ids,
        ctx=ctx,
        end_ts=end_ts,
        logger=logger,
    )
    if not chunks:
        logger.warning("text_summarizer: No chunks found.")
        return

    logger.debug("Fetched %d chunks for text_summarizer", len(chunks))

    summarizer = TextSummarizer()
    summarizer.logger = logger

    episode_summaries = summarizer.summarize_all_episodes(chunks)
    chapter_summaries = summarizer.summarize_all_chapters(chunks)

    logger.info(
        "Prepared summaries: episodes=%d chapters=%d dry_run=%s",
        len(episode_summaries),
        len(chapter_summaries),
        args.dry_run,
    )

    if args.dry_run or ctx.dry_run:
        logger.info("Dry run enabled: skipping summary writes and commit")
        return

    logger.info("Starting Update: Episode")
    total_updates = 0
    total_updates += update_episode_summaries(
        conn,
        episode_summaries,
        args.batch_id,
        ctx.processing_update_ts,
    )
    logger.info("Starting Update: Chapter")
    total_updates += update_chapter_summaries(
        conn,
        chapter_summaries,
        args.batch_id,
        ctx.processing_update_ts,
    )
    conn.commit()
    logger.info("Rows updated: %d", total_updates)
    logger.info("End step: text_summarizer")


def main() -> None:
    args = parse_args()
    connector = DbConnector()

    logger = AppLogger(
        module_name="text_summarizer_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    ).build()

    with connector.get_connection() as conn:
        watermark = connector.parse_ts(args.watermark)
        if args.mode == "delta":
            if watermark is None:
                watermark = connector.get_watermark(conn, args.stage)
        logger.info("Start watermark: %s", watermark)
        logger.info("End watermark: %s", args.test_end_watermark)
        ctx = LoadContext(
            mode=args.mode,
            watermark=watermark,
            connector=connector,
            logger=logger,
            dry_run=args.dry_run,
        )

        run_step(conn, ctx, args)


if __name__ == "__main__":
    main()
