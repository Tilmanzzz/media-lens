from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Set, Tuple

from common.db_connector import DbConnector


@dataclass
class LoadContext:
    mode: str
    connector: DbConnector
    watermark: Optional[datetime]
    processing_update_ts: Optional[datetime] = None


def should_include(processing_update_ts: Optional[datetime], ctx: LoadContext) -> bool:
    if ctx.mode == "full":
        print("  mode is full => include all")
        return True
    if ctx.watermark is None:
        print("  watermark is None => include all")
        return True
    if processing_update_ts is None:
        print("  processing_update_ts is None => include")
        return True
    return processing_update_ts > ctx.watermark


def should_include_between(
    processing_update_ts: Optional[datetime],
    start_ts: Optional[datetime],
    end_ts: Optional[datetime],
) -> bool:
    if processing_update_ts is None:
        return True
    if start_ts is not None and processing_update_ts <= start_ts:
        return False
    if end_ts is not None and processing_update_ts > end_ts:
        return False
    return True


def fetch_delta_targets(conn, ctx: LoadContext, update_ts_level: str = "chapter") -> Tuple[Set[str], Set[str]]:
    if ctx.mode == "full":
        return set(), set()

    if update_ts_level not in {"chapter", "episode", "podcast"}:
        raise ValueError(f"Unknown update_ts_level: {update_ts_level}")

    params: List[Any] = []

    if ctx.watermark is not None:
        # choose the processing_updated_at expression according to requested level
        if update_ts_level == "chapter":
            expr = "COALESCE(ch.processing_updated_at, ch.preprocessing_updated_at, e.source_system_updated_at, TIMESTAMPTZ '1970-01-01')"
            sql = f"""
        SELECT DISTINCT e.id AS episode_id, ch.id AS chapter_id
        FROM episodes e
        JOIN chapter ch ON ch.episode_id = e.id
        WHERE {expr} > %s OR ch.processing_updated_at IS NULL
    """
            params.append(ctx.watermark)
        elif update_ts_level == "episode":
            expr = "COALESCE(e.processing_updated_at, e.source_system_updated_at, TIMESTAMPTZ '1970-01-01')"
            sql = f"""
        SELECT DISTINCT e.id AS episode_id, ch.id AS chapter_id
        FROM episodes e
        JOIN chapter ch ON ch.episode_id = e.id
        WHERE {expr} > %s OR ch.processing_updated_at IS NULL
    """
            params.append(ctx.watermark)
        else:  # podcast
            expr = "COALESCE(p.processing_updated_at, p.source_system_updated_at, TIMESTAMPTZ '1970-01-01')"
            sql = f"""
        SELECT DISTINCT e.id AS episode_id, ch.id AS chapter_id
        FROM podcasts p
        JOIN episodes e ON e.podcast_id = p.id
        JOIN chapter ch ON ch.episode_id = e.id
        WHERE {expr} > %s OR ch.processing_updated_at IS NULL
    """
            params.append(ctx.watermark)
    else:
        # no watermark => select all
        sql = f"""
        SELECT DISTINCT e.id AS episode_id, ch.id AS chapter_id
        FROM episodes e
        JOIN chapter ch ON ch.episode_id = e.id
    """

    episode_ids: Set[str] = set()
    chapter_ids: Set[str] = set()

    with conn.cursor() as cur:
        cur.execute(sql, params)
        for row in cur.fetchall():
            episode_ids.add(str(row[0]))
            chapter_ids.add(str(row[1]))

    return episode_ids, chapter_ids


def fetch_chunks(
    conn,
    episode_ids: Optional[Set[str]] = None,
    chapter_ids: Optional[Set[str]] = None,
    update_ts_level: str = "chapter",
) -> List[Dict[str, Any]]:
    where_parts: List[str] = []
    params: List[Any] = []

    if episode_ids:
        where_parts.append("e.id = ANY(%s)")
        params.append(list(episode_ids))
    if chapter_ids:
        where_parts.append("ch.id = ANY(%s)")
        params.append(list(chapter_ids))

    where_clause = ""
    if where_parts:
        where_clause = "WHERE " + " OR ".join(where_parts)

    if update_ts_level not in {"chapter", "episode", "podcast"}:
        raise ValueError(f"Unknown update_ts_level: {update_ts_level}")

    # use processing_updated_at for watermark/delta semantics, with epoch fallback for NULLs
    processing_update_ts_expr = {
        "chapter": "ch.processing_updated_at",
        "episode": "e.processing_updated_at",
        "podcast": "p.processing_updated_at",
    }[update_ts_level]

    sql = f"""
        SELECT
            p.id AS podcast_id,
            p.title AS podcast_title,
            e.id AS episode_id,
            e.title AS episode_title,
            ch.id AS chapter_id,
            ch.title AS chapter_title,
            ch.transcript AS transcript_text,
            {processing_update_ts_expr} AS source_update_ts
        FROM podcasts p
        JOIN episodes e ON e.podcast_id = p.id
        JOIN chapter ch ON ch.episode_id = e.id
        {where_clause}
        ORDER BY e.id, ch.chapter_idx
    """

    chunks: List[Dict[str, Any]] = []
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        for row in rows:
            chunks.append(
                {
                    "podcast_id": row[0],
                    "podcast_title": row[1] or "",
                    "episode_id": row[2],
                    "episode_title": row[3] or "",
                    "chapter_id": row[4],
                    "chapter_title": row[5] or "",
                    "transcript_text": row[6] or "",
                    "source_update_ts": row[7],
                }
            )
    return chunks


def fetch_chapter_ids_for_episode(
    conn,
    episode_id: str,
    limit: int,
) -> List[str]:
    sql = """
        SELECT ch.id
        FROM chapter ch
        WHERE ch.episode_id = %s
        ORDER BY ch.chapter_idx
        LIMIT %s
    """
    with conn.cursor() as cur:
        cur.execute(sql, (episode_id, limit))
        return [str(row[0]) for row in cur.fetchall()]


def expand_targets_from_chunks(chunks: List[Dict[str, Any]]) -> Tuple[Set[str], Set[str]]:
    episode_ids: Set[str] = set()
    chapter_ids: Set[str] = set()
    for chunk in chunks:
        episode_id = chunk.get("episode_id")
        chapter_id = chunk.get("chapter_id")
        if episode_id:
            episode_ids.add(str(episode_id))
        if chapter_id:
            chapter_ids.add(str(chapter_id))
    return episode_ids, chapter_ids


def start_pipeline_batch(conn, stage: str, load_mode: str) -> str:
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
    return batch_id


def finalize_pipeline_batch(conn, batch_id: str, status: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE pipeline_batches SET status = %s, fin_ts = NOW() WHERE id = %s",
            (status, batch_id),
        )
    conn.commit()
