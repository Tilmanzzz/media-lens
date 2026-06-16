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
) -> str:
    chunk_id = chunk.get("chapter_id") or chunk.get("transcript_line_id") or chunk.get("episode_id") or chunk.get("podcast_id")
    preprocessing_update_at = chunk.get("preprocessing_update_ts")
    processing_update_at = chunk.get("processing_update_ts")

    if ctx is None or ctx.mode == "full":
        state = "full_load"
    elif processing_update_at is None:
        state = "no_processing_ts"
    elif preprocessing_update_at is not None and preprocessing_update_at > processing_update_at:
        state = "preprocessing_gt_processing"
    else:
        state = "processing_gte_preprocessing"

    return (
        f"chunk={chunk_id} step={step} level={level} reason={state} "
        f"preprocessing_updated_at={preprocessing_update_at} processing_updated_at={processing_update_at} "
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
                , ch.processing_updated_at AS processing_update_ts
            """,
            "from_sql": """
                FROM chapters ch
                JOIN episodes e ON e.id = ch.episode_id
            """,
            "order_by": "e.id, ch.chapter_idx",
            "preprocessing_ts": "ch.preprocessing_updated_at",
            "processing_ts": "ch.processing_updated_at",
            "preprocessing_table": "chapters",
            "preprocessing_column": "preprocessing_updated_at",
            "processing_table": "chapters",
            "processing_column": "processing_updated_at",
        }

    if step == "fact_checker":
        return {
            "id_column": "ch.id",
            "select_sql": """
                e.id AS episode_id,
                ch.id AS chapter_id,
                ch.transcript AS transcript_text
                , MAX(fc.processing_updated_at) AS processing_update_ts
                , ch.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM chapters ch
                JOIN episodes e ON e.id = ch.episode_id
                LEFT JOIN fact_checked_claims fc ON fc.chapter_id = ch.id
            """,
            "group_by": "e.id, ch.id, ch.transcript, ch.preprocessing_updated_at",
            "order_by": "e.id, ch.chapter_idx",
            "preprocessing_ts": "ch.preprocessing_updated_at",
            "processing_ts": "MAX(fc.processing_updated_at)",
            "processing_ts_is_agg": "true",
            "preprocessing_table": "chapters",
            "preprocessing_column": "preprocessing_updated_at",
            "processing_table": "fact_checked_claims",
            "processing_column": "processing_updated_at",
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
                , tl.processing_updated_at AS processing_update_ts
                , tl.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM transcript_lines tl
                JOIN chapters ch ON ch.id = tl.chapter_id
                JOIN episodes e ON e.id = ch.episode_id
            """,
            "order_by": "e.id, ch.chapter_idx, tl.line_idx",
            "preprocessing_ts": "tl.preprocessing_updated_at",
            "processing_ts": "tl.processing_updated_at",
            "preprocessing_table": "transcript_lines",
            "preprocessing_column": "preprocessing_updated_at",
            "processing_table": "transcript_lines",
            "processing_column": "processing_updated_at",
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
                    , MAX(em.processing_updated_at) AS processing_update_ts
                    , ch.preprocessing_updated_at AS preprocessing_update_ts
                """,
                "from_sql": """
                    FROM chapters ch
                    LEFT JOIN embeddings em
                        ON em.chapter_id = ch.id
                        AND em.level = 'chapter'
                """,
                "group_by": "ch.id, ch.transcript, ch.preprocessing_updated_at",
                "order_by": "ch.episode_id, ch.chapter_idx",
                "preprocessing_ts": "ch.preprocessing_updated_at",
                "processing_ts": "MAX(em.processing_updated_at)",
                "processing_ts_is_agg": "true",
                "preprocessing_table": "chapters",
                "preprocessing_column": "preprocessing_updated_at",
                "processing_table": "embeddings",
                "processing_column": "processing_updated_at",
                "processing_filter": "level = 'chapter'",
            }

        if level == "episode":
            return {
                "id_column": "e.id",
                "select_sql": """
                    e.id AS episode_id,
                    e.summary AS episode_summary
                    , MAX(em.processing_updated_at) AS processing_update_ts
                    , e.preprocessing_updated_at AS preprocessing_update_ts
                """,
                "from_sql": """
                    FROM episodes e
                    LEFT JOIN embeddings em
                        ON em.episode_id = e.id
                        AND em.level = 'episode'
                """,
                "group_by": "e.id, e.summary, e.preprocessing_updated_at",
                "order_by": "e.id",
                "preprocessing_ts": "e.preprocessing_updated_at",
                "processing_ts": "MAX(em.processing_updated_at)",
                "processing_ts_is_agg": "true",
                "preprocessing_table": "episodes",
                "preprocessing_column": "preprocessing_updated_at",
                "processing_table": "embeddings",
                "processing_column": "processing_updated_at",
                "processing_filter": "level = 'episode'",
            }

        return {
            "id_column": "p.id",
            "select_sql": """
                p.id AS podcast_id,
                p.title AS podcast_title
                , MAX(em.processing_updated_at) AS processing_update_ts
                , p.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM podcasts p
                LEFT JOIN embeddings em
                    ON em.podcast_id = p.id
                    AND em.level = 'podcast'
            """,
            "group_by": "p.id, p.title, p.preprocessing_updated_at",
            "order_by": "p.title, p.id",
            "preprocessing_ts": "p.preprocessing_updated_at",
            "processing_ts": "MAX(em.processing_updated_at)",
            "processing_ts_is_agg": "true",
            "preprocessing_table": "podcasts",
            "preprocessing_column": "preprocessing_updated_at",
            "processing_table": "embeddings",
            "processing_column": "processing_updated_at",
            "processing_filter": "level = 'podcast'",
        }

    raise ValueError(f"Unsupported fetch step: {step}")


def _fetch_target_watermark_value(conn, spec: Dict[str, str]) -> Any:
    table = spec["processing_table"]
    column = spec["processing_column"]
    filter_sql = spec.get("processing_filter")
    where_clause = f"WHERE {filter_sql}" if filter_sql else ""
    sql = f"SELECT MAX({column}) FROM {table} {where_clause}"
    with conn.cursor() as cur:
        cur.execute(sql)
        row = cur.fetchone()
    return row[0] if row else None


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

    having_parts: List[str] = []
    if ctx is not None and ctx.mode == "delta":
        processing_is_agg = spec.get("processing_ts_is_agg") == "true"
        target_parts = having_parts if processing_is_agg else where_parts
        preprocessing_ts = spec["preprocessing_ts"]
        processing_ts = spec["processing_ts"]
        if end_ts is None:
            target_parts.append(f"({preprocessing_ts} > {processing_ts} OR {processing_ts} IS NULL)")
        else:
            target_parts.append(
                f"(({preprocessing_ts} > {processing_ts} AND {preprocessing_ts} <= %s) OR {processing_ts} IS NULL)"
            )
            params.append(end_ts)

    where_clause = ""
    if where_parts:
        where_clause = "WHERE " + " AND ".join(where_parts)

    group_by = spec.get("group_by")
    group_clause = f"GROUP BY {group_by}" if group_by else ""
    having_clause = ""
    if having_parts:
        having_clause = "HAVING " + " AND ".join(having_parts)

    sql = f"""
        SELECT
        {spec['select_sql']}
        {spec['from_sql']}
        {where_clause}
        {group_clause}
        {having_clause}
        ORDER BY {spec['order_by']}
    """

    if logger is not None:
        logger.info(
            "DB fetch start: step=%s level=%s mode=%s ids=%s test_end_ts=%s",
            step,
            level or "-",
            ctx.mode if ctx is not None else "full",
            len(ids) if ids is not None else "all",
            end_ts,
        )
        if ctx is not None and ctx.mode == "delta":
            target_watermark_value = _fetch_target_watermark_value(conn, spec)
            logger.info(
                "delta watermark check: step=%s level=%s source=%s.%s target=%s.%s target_current_max=%s",
                step,
                level or "-",
                spec["preprocessing_table"],
                spec["preprocessing_column"],
                spec["processing_table"],
                spec["processing_column"],
                target_watermark_value,
            )

    chunks: List[Dict[str, Any]] = []
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        column_names = [column[0] for column in cur.description]

        if logger is not None:
            logger.info("DB fetch done: step=%s level=%s rows=%d", step, level or "-", len(rows))

        for row in rows:
            chunk = dict(zip(column_names, row))
            debug_message = _format_delta_debug(step, level, chunk, ctx, end_ts)
            if logger is not None:
                logger.debug(debug_message)
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
    if logger is not None:
        logger.info("DB query start: chapter_ids episode=%s limit=%s", episode_id, limit)
    with conn.cursor() as cur:
        cur.execute(sql, (episode_id, limit))
        chapter_ids = [str(row[0]) for row in cur.fetchall()]
    if logger is not None:
        logger.info("DB query done: chapter_ids episode=%s rows=%d", episode_id, len(chapter_ids))
    return chapter_ids


def start_pipeline_batch(conn, stage: str, load_mode: str, logger: Optional[logging.Logger] = None) -> str:
    if logger is not None:
        logger.info("DB write start: pipeline_batch stage=%s load_mode=%s", stage, load_mode)
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
        logger.info("DB write done: pipeline_batch id=%s stage=%s load_mode=%s", batch_id, stage, load_mode)
    return batch_id


def finalize_pipeline_batch(conn, batch_id: str, status: str, logger: Optional[logging.Logger] = None) -> None:
    if logger is not None:
        logger.info("DB write start: pipeline_batch id=%s status=%s", batch_id, status)
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE pipeline_batches SET status = %s, fin_ts = NOW() WHERE id = %s",
            (status, batch_id),
        )
    conn.commit()
    if logger is not None:
        logger.info("DB write done: pipeline_batch id=%s status=%s", batch_id, status)


@contextmanager
def pipeline_batch_scope(
    conn,
    stage: str,
    load_mode: str,
    batch_id: Optional[str],
    dry_run: bool,
    logger: Optional[logging.Logger] = None,
) -> Iterator[Optional[str]]:
    """Documents a step run in pipeline_batches; does not influence delta filtering.

    If batch_id is already provided (e.g. via --batch-id), that batch is assumed to be
    owned/finalized by the caller and is only used to tag rows.
    """
    owns_batch = batch_id is None and not dry_run
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
                    logger.exception("pipeline_batch: rollback failed")
            try:
                finalize_pipeline_batch(conn, batch_id, "failed", logger=logger)
            except Exception:
                if logger is not None:
                    logger.exception("pipeline_batch: failed to finalize batch as failed")
        raise
    else:
        if owns_batch:
            finalize_pipeline_batch(conn, batch_id, "success", logger=logger)
