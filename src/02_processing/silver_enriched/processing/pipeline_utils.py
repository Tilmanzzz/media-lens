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


def should_include(source_ts: Optional[datetime], ctx: LoadContext) -> bool:
    if ctx.mode == "full":
        return True
    if ctx.watermark is None:
        return True
    return source_ts > ctx.watermark


def should_include_between(
    source_ts: Optional[datetime],
    start_ts: Optional[datetime],
    end_ts: Optional[datetime],
) -> bool:
    if source_ts is None:
        return False
    if start_ts is not None and source_ts <= start_ts:
        return False
    if end_ts is not None and source_ts > end_ts:
        return False
    return True


def fetch_delta_targets(conn, ctx: LoadContext) -> Tuple[Set[str], Set[str]]:
    if ctx.mode == "full":
        return set(), set()

    clause = ""
    params: List[Any] = []
    if ctx.watermark is not None:
        clause = "WHERE COALESCE(ch.system_updated_at, e.system_updated_at, e.updated_at) > %s"
        params.append(ctx.watermark)

    sql = f"""
        SELECT DISTINCT e.id AS episode_id, ch.id AS chapter_id
        FROM episodes e
        JOIN chapter ch ON ch.episode_id = e.id
        {clause}
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

    sql = f"""
        SELECT
            p.id AS podcast_id,
            p.title AS podcast_title,
            e.id AS episode_id,
            e.title AS episode_title,
            ch.id AS chapter_id,
            ch.transcript AS transcript_text,
            COALESCE(ch.system_updated_at, e.system_updated_at, e.updated_at) AS source_update_ts
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
                    "transcript_text": row[5] or "",
                    "source_update_ts": row[6],
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
            INSERT INTO pipeline_batches (stage, load_mode, status, start_ts, fin_ts, updated_at)
            VALUES (%s, %s, 'pending', NOW(), NOW(), NOW())
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
            "UPDATE pipeline_batches SET status = %s, fin_ts = NOW(), updated_at = NOW() WHERE id = %s",
            (status, batch_id),
        )
    conn.commit()
