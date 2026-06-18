from __future__ import annotations

import json
import logging
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional, Set

from common.app_logger import AppLogger
from common.db_connector import DbConnector


@dataclass
class LoadContext:
    mode: str
    connector: DbConnector
    processing_update_ts: Optional[datetime] = None
    logger: Optional[AppLogger] = None
    dry_run: bool = False


def load_json_config(config_path: Optional[str], base_dir: Optional[Path] = None) -> Dict[str, Any]:
    if not config_path:
        return {}

    path = Path(config_path).expanduser()
    if not path.is_absolute():
        if base_dir is not None:
            path = base_dir / path
        else:
            path = Path(__file__).resolve().parent / path

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if not isinstance(data, dict):
        raise ValueError(f"Config file must contain a JSON object: {path}")

    return data


def build_pipeline_logger(
    module_name: str,
    enabled: bool,
    level: str,
    log_dir: Optional[str],
    log_file: Optional[str],
) -> logging.Logger:
    return AppLogger(
        module_name=module_name,
        enabled=enabled,
        level=level,
        log_dir=log_dir,
        log_file=log_file,
    ).build()


def _format_delta_debug(
    step: str,
    level: Optional[str],
    chunk: Dict[str, Any],
    ctx: Optional[LoadContext],
    end_ts: Optional[datetime],
    batch_watermark: Optional[datetime] = None,
) -> str:
    chunk_id = chunk.get("chapter_id") or chunk.get("transcript_line_id") or chunk.get("episode_id") or chunk.get("podcast_id")
    preprocessing_update_at = chunk.get("preprocessing_update_ts")

    if ctx is None or ctx.mode == "full":
        state = "full_load"
    elif batch_watermark is None:
        state = "no_batch_watermark"
    elif preprocessing_update_at is not None and preprocessing_update_at > batch_watermark:
        state = "preprocessing_gt_watermark"
    else:
        state = "preprocessing_lte_watermark"

    return (
        f"chunk={chunk_id} step={step} level={level} reason={state} "
        f"preprocessing_updated_at={preprocessing_update_at} stage_watermark={batch_watermark} "
        f"test_end_ts={end_ts}"
    )


def _build_fetch_spec(step: str, level: Optional[str]) -> Dict[str, str]:
    if step == "text_summarizer":
        return {
            "id_column": "ch.id",
            "select_sql": """
                e.id AS episode_id,
                ch.id AS chapter_id,
                ch.transcript AS transcript_text
                , ch.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM chapters ch
                JOIN episodes e ON e.id = ch.episode_id
            """,
            "order_by": "e.id, ch.chapter_idx",
            "preprocessing_ts": "ch.preprocessing_updated_at",
            "batch_stage": "text_summarizer",
            "preprocessing_table": "chapters",
            "preprocessing_column": "preprocessing_updated_at",
        }

    if step == "fact_checker":
        return {
            "id_column": "ch.id",
            "select_sql": """
                e.id AS episode_id,
                ch.id AS chapter_id,
                ch.transcript AS transcript_text
                , ch.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM chapters ch
                JOIN episodes e ON e.id = ch.episode_id
            """,
            "order_by": "e.id, ch.chapter_idx",
            "preprocessing_ts": "ch.preprocessing_updated_at",
            "batch_stage": "fact_checker",
            "preprocessing_table": "chapters",
            "preprocessing_column": "preprocessing_updated_at",
        }

    if step == "emotion_scoring":
        if level not in {None, "transcript_lines"}:
            raise ValueError(f"Unsupported level for emotion_scoring: {level}")
        return {
            "id_column": "tl.id",
            "select_sql": """
                e.id AS episode_id,
                tl.id AS transcript_line_id,
                tl.line_idx AS line_idx,
                tl.start_time AS start_time,
                tl.end_time AS end_time
                , tl.text AS transcript_text
                , e.audio_key AS audio_key
                , tl.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM transcript_lines tl
                JOIN chapters ch ON ch.id = tl.chapter_id
                JOIN episodes e ON e.id = ch.episode_id
            """,
            "order_by": "e.id, ch.chapter_idx, tl.line_idx",
            "preprocessing_ts": "tl.preprocessing_updated_at",
            "batch_stage": "emotion_scoring",
            "preprocessing_table": "transcript_lines",
            "preprocessing_column": "preprocessing_updated_at",
        }

    if step == "embedding":
        if level not in {"chapter", "episode", "podcast"}:
            raise ValueError(f"Unsupported embedding level: {level}")

        if level == "chapter":
            return {
                "id_column": "ch.id",
                "select_sql": """
                    ch.id AS chapter_id,
                    ch.transcript AS transcript_text
                    , ch.preprocessing_updated_at AS preprocessing_update_ts
                """,
                "from_sql": "FROM chapters ch",
                "order_by": "ch.episode_id, ch.chapter_idx",
                "preprocessing_ts": "ch.preprocessing_updated_at",
                "batch_stage": "embedder",
                "preprocessing_table": "chapters",
                "preprocessing_column": "preprocessing_updated_at",
            }

        if level == "episode":
            return {
                "id_column": "e.id",
                "select_sql": """
                    e.id AS episode_id,
                    e.summary AS episode_summary
                    , e.preprocessing_updated_at AS preprocessing_update_ts
                """,
                "from_sql": "FROM episodes e",
                "order_by": "e.id",
                "preprocessing_ts": "e.preprocessing_updated_at",
                "batch_stage": "embedder",
                "preprocessing_table": "episodes",
                "preprocessing_column": "preprocessing_updated_at",
            }

        return {
            "id_column": "p.id",
            "select_sql": """
                p.id AS podcast_id,
                p.title AS podcast_title
                , p.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": "FROM podcasts p",
            "order_by": "p.title, p.id",
            "preprocessing_ts": "p.preprocessing_updated_at",
            "batch_stage": "embedder",
            "preprocessing_table": "podcasts",
            "preprocessing_column": "preprocessing_updated_at",
        }

    raise ValueError(f"Unsupported fetch step: {step}")


def fetch_stage_watermark(conn, stage: str) -> Optional[datetime]:
    sql = """
        SELECT MAX(start_ts)
        FROM pipeline_batches
        WHERE stage::text = %s AND status = 'success'
    """
    with conn.cursor() as cur:
        cur.execute(sql, (stage,))
        row = cur.fetchone()
    return row[0] if row else None


def fetch_db_now(conn) -> datetime:
    with conn.cursor() as cur:
        cur.execute("SELECT NOW()")
        return cur.fetchone()[0]


def fetch_chunks(
    conn,
    step: str,
    level: Optional[str] = None,
    ids: Optional[Set[str]] = None,
    ctx: Optional[LoadContext] = None,
    end_ts: Optional[datetime] = None,
    logger: Optional[logging.Logger] = None,
) -> List[Dict[str, Any]]:
    spec = _build_fetch_spec(step, level)

    where_parts: List[str] = []
    params: List[Any] = []

    if ids:
        where_parts.append(f"{spec['id_column']} = ANY(%s)")
        params.append(list(ids))

    batch_watermark: Optional[datetime] = None
    if ctx is not None and ctx.mode == "delta":
        preprocessing_ts = spec["preprocessing_ts"]
        batch_watermark = fetch_stage_watermark(conn, spec["batch_stage"])
        if batch_watermark is not None and end_ts is not None:
            where_parts.append(f"({preprocessing_ts} > %s AND {preprocessing_ts} <= %s)")
            params.append(batch_watermark)
            params.append(end_ts)
        elif batch_watermark is not None:
            where_parts.append(f"{preprocessing_ts} > %s")
            params.append(batch_watermark)
        elif end_ts is not None:
            where_parts.append(f"{preprocessing_ts} <= %s")
            params.append(end_ts)

    where_clause = ""
    if where_parts:
        where_clause = "WHERE " + " AND ".join(where_parts)

    sql = f"""
        SELECT
        {spec['select_sql']}
        {spec['from_sql']}
        {where_clause}
        ORDER BY {spec['order_by']}
    """

    chunks: List[Dict[str, Any]] = []
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        column_names = [column[0] for column in cur.description]

        for row in rows:
            chunk = dict(zip(column_names, row))
            debug_message = _format_delta_debug(step, level, chunk, ctx, end_ts, batch_watermark)
            if logger is not None:
                logger.debug(debug_message)

    if logger is not None:
        mode = ctx.mode if ctx is not None else "full"
        if mode == "delta":
            logger.info(
                "fetch_chunks: step=%s level=%s mode=delta watermark=%s rows=%d",
                step, level or "-", batch_watermark, len(rows),
            )
        else:
            logger.info(
                "fetch_chunks: step=%s level=%s mode=full rows=%d",
                step, level or "-", len(rows),
            )
            chunks.append(chunk)

    return chunks


def fetch_chapter_ids_for_episode(
    conn,
    episode_id: str,
    limit: int,
    logger: Optional[logging.Logger] = None,
) -> List[str]:
    sql = """
        SELECT ch.id
        FROM chapters ch
        WHERE ch.episode_id = %s
        ORDER BY ch.chapter_idx
        LIMIT %s
    """
    with conn.cursor() as cur:
        cur.execute(sql, (episode_id, limit))
        chapter_ids = [str(row[0]) for row in cur.fetchall()]
    if logger is not None:
        logger.info("fetch: chapter_ids episode_id=%s rows=%d", episode_id, len(chapter_ids))
    return chapter_ids


def start_pipeline_batch(conn, stage: str, load_mode: str, logger: Optional[logging.Logger] = None) -> str:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO pipeline_batches (stage, load_mode, status, start_ts, fin_ts)
            VALUES (%s, %s, 'pending', NOW(), NOW())
            RETURNING id
            """,
            (stage, load_mode),
        )
        batch_id = str(cur.fetchone()[0])
    conn.commit()
    if logger is not None:
        logger.info("pipeline_batch: created batch_id=%s stage=%s mode=%s", batch_id, stage, load_mode)
    return batch_id


def finalize_pipeline_batch(conn, batch_id: str, status: str, logger: Optional[logging.Logger] = None) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE pipeline_batches SET status = %s, fin_ts = NOW() WHERE id = %s",
            (status, batch_id),
        )
    conn.commit()
    if logger is not None:
        logger.info("pipeline_batch: finalized batch_id=%s status=%s", batch_id, status)


@contextmanager
def pipeline_batch_scope(
    conn,
    stage: str,
    load_mode: str,
    batch_id: Optional[str],
    dry_run: bool,
    logger: Optional[logging.Logger] = None,
) -> Iterator[Optional[str]]:
    owns_batch = batch_id is None and not dry_run
    if dry_run and logger is not None:
        logger.info("pipeline_batch: dry run, no batch created stage=%s", stage)
    if owns_batch:
        batch_id = start_pipeline_batch(conn, stage, load_mode, logger=logger)

    try:
        yield batch_id
    except BaseException:
        if owns_batch:
            try:
                conn.rollback()
            except Exception:
                if logger is not None:
                    logger.exception("pipeline_batch: rollback failed stage=%s batch_id=%s", stage, batch_id)
            try:
                finalize_pipeline_batch(conn, batch_id, "failed", logger=logger)
            except Exception:
                if logger is not None:
                    logger.exception("pipeline_batch: could not finalize as failed batch_id=%s", batch_id)
        raise
    else:
        if owns_batch:
            finalize_pipeline_batch(conn, batch_id, "success", logger=logger)
