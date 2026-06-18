from __future__ import annotations

import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src\\02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

from common.app_logger import AppLogger
from common.db_connector import DbConnector
from silver_enriched.fact_checker.fact_checker_core import FactChecker
from silver_enriched.processing_pipeline.pipeline_utils import (
    LoadContext, build_pipeline_logger, fetch_chapter_ids_for_episode,
    fetch_chunks, fetch_db_now, load_json_config, pipeline_batch_scope)


def parse_args() -> argparse.Namespace:
    pre_parser = argparse.ArgumentParser(add_help=False)
    pre_parser.add_argument("--config", default=None, help="Path to pipeline args JSON config")
    pre_args, remaining = pre_parser.parse_known_args()

    parser = argparse.ArgumentParser(description="Run fact_checker against chapter transcripts (full or delta).")
    parser.add_argument("--config", default="processing_pipeline_config.json", help="Path to pipeline args JSON config")
    parser.add_argument("--mode", choices=["full", "delta"], default="delta")
    parser.add_argument("--stage", default="fact_checker", help="pipeline_batches.stage tag (documentation only)")
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
    parser.add_argument("--log-file", default="fact_checker_pipeline.log", help="Pipeline log file name")

    config = load_json_config(pre_args.config or parser.get_default("config"), base_dir=Path(__file__).resolve().parent)
    if config:
        parser.set_defaults(**config)

    return parser.parse_args(remaining)


def _normalize_sources(sources: Any) -> List[str]:
    if not isinstance(sources, list):
        return []

    normalized: List[str] = []
    for source in sources:
        value = str(source).strip()
        if value:
            normalized.append(value)
    return normalized


def upsert_fact_checked_claims(
    conn,
    chapter_results: Iterable[Dict[str, Any]],
    batch_id: Optional[str],
    processing_update_ts: Optional[datetime],
    logger=None,
) -> int:
    if processing_update_ts is None:
        raise ValueError("processing_update_ts is required for processing writes")

    rows: List[tuple] = []
    for chapter_result in chapter_results:
        chapter_id = chapter_result.get("chapter_id")
        claims = chapter_result.get("claims") or []
        if not chapter_id or not isinstance(claims, list):
            continue

        for claim_idx, claim_data in enumerate(claims):
            if not isinstance(claim_data, dict):
                continue

            claim_text = claim_data.get("claim")
            if not claim_text:
                continue

            rows.append(
                (
                    chapter_id,
                    claim_idx,
                    str(claim_text).strip(),
                    str(claim_data.get("verdict") or "UNVERIFIABLE").strip().upper(),
                    str(claim_data.get("explanation") or "").strip(),
                    _normalize_sources(claim_data.get("sources")),
                    batch_id,
                    processing_update_ts,
                )
            )

    if logger is not None:
        logger.info("DB write start: fact_checked_claims count=%d batch_id=%s", len(rows), batch_id or "-")

    sql = """
        INSERT INTO fact_checked_claims (
            chapter_id,
            claim_idx,
            claim,
            verdict,
            explanation,
            sources,
            batch_id,
            processing_updated_at
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (chapter_id, claim_idx)
        DO UPDATE SET
            claim = EXCLUDED.claim,
            verdict = EXCLUDED.verdict,
            explanation = EXCLUDED.explanation,
            sources = EXCLUDED.sources,
            batch_id = EXCLUDED.batch_id,
            processing_updated_at = EXCLUDED.processing_updated_at
    """

    with conn.cursor() as cur:
        if rows:
            cur.executemany(sql, rows)
        updated = len(rows)

    if logger is not None:
        logger.info("DB write done: fact_checked_claims rows=%d", updated)

    return updated


def run_step(conn, ctx: LoadContext, args: argparse.Namespace) -> None:
    logger = ctx.logger or build_pipeline_logger(
        module_name="fact_checker_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    )

    dry_run = args.dry_run or ctx.dry_run
    with pipeline_batch_scope(conn, args.stage, ctx.mode, args.batch_id, dry_run, logger=logger) as batch_id:
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
                logger.warning("fact_checker: no test chapters")
                return

        chunks = fetch_chunks(
            conn,
            step="fact_checker",
            level="chapter",
            ids=chapter_ids,
            ctx=ctx,
            end_ts=end_ts,
            logger=logger,
        )
        if not chunks:
            logger.warning("fact_checker: no chunks")
            return

        logger.info("fact_checker: chunks=%d", len(chunks))

        checker = FactChecker(
            config_path="fact_checker_config.json",
            logging_enabled=args.log_enabled,
            log_level=args.log_level,
        )
        checker.logger = logger

        def process_chunk(chunk: Dict[str, Any]) -> Optional[Dict[str, Any]]:
            transcript = str(chunk.get("transcript_text") or "").strip()
            chapter_id = chunk.get("chapter_id")
            if not chapter_id or not transcript:
                return None

            logger.info("fact_checker: start chapter_id=%s", chapter_id)
            result = checker.fact_check(transcript)
            claims = result.get("claims") if isinstance(result, dict) else []
            if not isinstance(claims, list):
                claims = []
            logger.info("fact_checker: done chapter_id=%s claims=%d", chapter_id, len(claims))
            return {"chapter_id": chapter_id, "claims": claims}

        max_chapter_workers = max(1, min(checker.config.max_chapter_workers, len(chunks)))
        with ThreadPoolExecutor(max_workers=max_chapter_workers) as executor:
            chapter_results = [
                result for result in executor.map(process_chunk, chunks) if result is not None
            ]

        if not chapter_results:
            logger.warning("fact_checker: no claims")
            return

        total_claims = sum(len(item.get("claims") or []) for item in chapter_results)
        logger.info("fact_checker: chapter_results=%d claims=%d", len(chapter_results), total_claims)

        if dry_run:
            logger.info("fact_checker: dry run, skip writes")
            return

        total_updates = upsert_fact_checked_claims(
            conn,
            chapter_results,
            batch_id,
            ctx.processing_update_ts,
            logger=logger,
        )
        logger.info("DB commit start: fact_checker rows=%d", total_updates)
        conn.commit()
        logger.info("DB commit done: fact_checker rows=%d", total_updates)
        logger.info("fact_checker: done rows=%d", total_updates)


def main() -> None:
    args = parse_args()
    connector = DbConnector()

    logger = AppLogger(
        module_name="fact_checker_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    ).build()

    with connector.get_connection(logger=logger) as conn:
        ctx = LoadContext(
            mode=args.mode,
            connector=connector,
            processing_update_ts=fetch_db_now(conn),
            logger=logger,
            dry_run=args.dry_run,
        )

        run_step(conn, ctx, args)


if __name__ == "__main__":
    main()