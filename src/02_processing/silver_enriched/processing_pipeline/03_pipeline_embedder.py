from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src\\02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

from common.app_logger import AppLogger
from common.db_connector import DbConnector
from silver_enriched.processing_pipeline.pipeline_utils import (
    LoadContext, build_pipeline_logger, fetch_chapter_ids_for_episode,
    fetch_chunks, load_json_config)
from silver_enriched.transcript_embedder.transcript_embedder_core import \
    TranscriptEmbedder


def parse_args() -> argparse.Namespace:
    pre_parser = argparse.ArgumentParser(add_help=False)
    pre_parser.add_argument("--config", default=None, help="Path to pipeline args JSON config")
    pre_args, remaining = pre_parser.parse_known_args()

    parser = argparse.ArgumentParser(description="Run embedder against podcast, episode, and chapter inputs.")
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
    parser.add_argument("--log-file", default="embedder_pipeline.log", help="Pipeline log file name")

    config = load_json_config(pre_args.config or parser.get_default("config"), base_dir=Path(__file__).resolve().parent)
    if config:
        parser.set_defaults(**config)

    return parser.parse_args(remaining)


def _fetch_podcast_id_for_episode(conn, episode_id: str, logger=None) -> Optional[str]:
    sql = "SELECT podcast_id FROM episodes WHERE id = %s"
    if logger is not None:
        logger.info("DB query start: podcast_id episode=%s", episode_id)
    with conn.cursor() as cur:
        cur.execute(sql, (episode_id,))
        row = cur.fetchone()
    podcast_id = str(row[0]) if row and row[0] is not None else None
    if logger is not None:
        logger.info("DB query done: podcast_id episode=%s podcast_id=%s", episode_id, podcast_id or "-")
    return podcast_id


def _build_input_chunks(level: str, chunks: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    inputs: List[Dict[str, Any]] = []
    for chunk in chunks:
        if level == "podcast":
            text = str(chunk.get("podcast_title") or "").strip()
            if not text:
                continue
            inputs.append({
                "podcast_id": chunk.get("podcast_id"),
                "transcription": text,
            })
        elif level == "episode":
            text = str(chunk.get("episode_summary") or "").strip()
            if not text:
                continue
            inputs.append({
                "episode_id": chunk.get("episode_id"),
                "transcription": text,
            })
        else:
            text = str(chunk.get("transcript_text") or "").strip()
            if not text:
                continue
            inputs.append({
                "chapter_id": chunk.get("chapter_id"),
                "transcription": text,
            })
    return inputs


def _build_embedding_rows(
    level: str,
    embedded: Iterable[Dict[str, Any]],
    batch_id: Optional[str],
    processing_update_ts: Optional[datetime],
) -> List[Dict[str, Any]]:
    if processing_update_ts is None:
        raise ValueError("processing_update_ts is required for processing writes")

    rows: List[Dict[str, Any]] = []
    for record in embedded:
        embedding = record.get("embedding")
        if not embedding:
            continue

        rows.append({
            "chapter_id": record.get("chapter_id") if level == "chapter" else None,
            "episode_id": record.get("episode_id") if level == "episode" else None,
            "podcast_id": record.get("podcast_id") if level == "podcast" else None,
            "level": level,
            "embedding": str(embedding),
            "batch_id": batch_id,
            "processing_updated_at": processing_update_ts,
        })

    return rows


def _insert_embeddings(
    conn,
    rows: List[Dict[str, Any]],
    logger=None,
) -> int:
    if not rows:
        return 0

    level = rows[0]["level"]
    if level == "podcast":
        conflict_target = "(podcast_id) WHERE level = 'podcast'"
    elif level == "episode":
        conflict_target = "(episode_id) WHERE level = 'episode'"
    else:
        conflict_target = "(chapter_id) WHERE level = 'chapter'"

    sql = (
        "INSERT INTO embeddings (chapter_id, episode_id, podcast_id, level, embedding, batch_id, processing_updated_at) "
        "VALUES (%(chapter_id)s, %(episode_id)s, %(podcast_id)s, %(level)s, %(embedding)s::halfvec, %(batch_id)s, %(processing_updated_at)s) "
        f"ON CONFLICT {conflict_target} DO UPDATE SET "
        "embedding = EXCLUDED.embedding, "
        "batch_id = EXCLUDED.batch_id, "
        "processing_updated_at = EXCLUDED.processing_updated_at"
    )

    if logger is not None:
        logger.info("DB write start: embeddings rows=%d level=%s", len(rows), level)

    with conn.cursor() as cur:
        cur.executemany(sql, rows)

    if logger is not None:
        logger.info("DB write done: embeddings rows=%d level=%s", len(rows), level)

    return len(rows)


def run_step(conn, ctx: LoadContext, args: argparse.Namespace) -> None:
    logger = ctx.logger or build_pipeline_logger(
        module_name="embedder_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    )

    end_ts = None
    if args.testing and args.test_end_watermark:
        end_ts = ctx.connector.parse_ts(args.test_end_watermark)

    chapter_ids: Optional[Set[str]] = None
    episode_ids: Optional[Set[str]] = None
    podcast_ids: Optional[Set[str]] = None

    if args.testing and args.test_episode_id:
        episode_ids = {str(args.test_episode_id)}
        chapter_ids = set(
            fetch_chapter_ids_for_episode(
                conn,
                str(args.test_episode_id),
                args.test_chapter_limit,
            )
        )
        if not chapter_ids:
            logger.warning("embedder: no test chapters")
            chapter_ids = None

        podcast_id = _fetch_podcast_id_for_episode(conn, str(args.test_episode_id), logger=logger)
        if podcast_id:
            podcast_ids = {podcast_id}

    embedder = TranscriptEmbedder(logging_enabled=args.log_enabled, log_level=args.log_level)
    embedder.logger = logger

    total_updates = 0

    for level in ("podcast", "episode", "chapter"):
        if level == "podcast":
            ids = podcast_ids
        elif level == "episode":
            ids = episode_ids
        else:
            ids = chapter_ids

        chunks = fetch_chunks(
            conn,
            step="embedding",
            level=level,
            ids=ids,
            ctx=ctx,
            end_ts=end_ts,
            logger=logger,
        )
        if not chunks:
            logger.warning("embedder: no chunks level=%s", level)
            continue

        inputs = _build_input_chunks(level, chunks)
        if not inputs:
            logger.warning("embedder: no valid inputs level=%s", level)
            continue

        logger.info("embedder: embedding level=%s inputs=%d", level, len(inputs))
        embedded = embedder.embed_chunks(inputs)

        if not embedded:
            logger.warning("embedder: empty embeddings level=%s", level)
            continue

        if args.dry_run or ctx.dry_run:
            logger.info("embedder: dry run, skip writes level=%s", level)
            continue

        rows = _build_embedding_rows(level, embedded, args.batch_id, ctx.processing_update_ts)
        total_updates += _insert_embeddings(conn, rows, logger=logger)

    if args.dry_run or ctx.dry_run:
        return

    logger.info("DB commit start: embedder rows=%d", total_updates)
    conn.commit()
    logger.info("DB commit done: embedder rows=%d", total_updates)
    logger.info("embedder: done rows=%d", total_updates)


def main() -> None:
    args = parse_args()
    connector = DbConnector()

    logger = AppLogger(
        module_name="embedder_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    ).build()

    with connector.get_connection(logger=logger) as conn:
        watermark = connector.parse_ts(args.watermark)
        if args.mode == "delta":
            if watermark is None:
                logger.info("watermark: resolve stage=%s", args.stage)
                watermark = connector.get_watermark(conn, args.stage, logger=logger)
        logger.info("watermark: mode=%s value=%s", args.mode, watermark)
        ctx = LoadContext(
            mode=args.mode,
            watermark=watermark,
            connector=connector,
            processing_update_ts=datetime.now(timezone.utc),
            logger=logger,
            dry_run=args.dry_run,
        )

        run_step(conn, ctx, args)


if __name__ == "__main__":
    main()
