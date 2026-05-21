from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Set

from common.db_connector import DbConnector


@dataclass
class LoadContext:
    mode: str
    connector: DbConnector
    watermark: Optional[datetime]
    processing_update_ts: Optional[datetime] = None


def _print_delta_debug(
    step: str,
    level: Optional[str],
    chunk: Dict[str, Any],
    ctx: Optional[LoadContext],
    end_ts: Optional[datetime],
) -> str:
    id = chunk.get("chapter_id") or chunk.get("transcript_line_id") or chunk.get("episode_id") or chunk.get("podcast_id")
    preprocessing_update_at = chunk.get("preprocessing_update_ts")
    processing_update_at =chunk.get("processing_update_ts")
    watermark = ctx.watermark if ctx is not None else None

    if ctx is None or ctx.mode == "full":
        state = "full load"
    elif watermark is None:
        state = "watermark is none"
    elif processing_update_at is None:
        state = "processing_update_at is None"
    elif watermark < preprocessing_update_at:
        state = "delta load (watermark < preprocessing_update_at)"
    else:
        state = "undefined"

    print(f"step={step} level={level} id={id}")
    print(f"  > state={state}")
    print(f"  > preprocessing_update_at={preprocessing_update_at}")
    print(f"  > processing_update_at={processing_update_at}")
    print(f"  > watermark_start_ts={watermark}")
    print(f"  > watermark_end_ts={end_ts}")

def _build_fetch_spec(step: str, level: Optional[str]) -> Dict[str, str]:
    if step == "text_summarizer" or step == "fact_checking":
        return {
            "id_column": "ch.id",
            "select_sql": """
                e.id AS episode_id,
                ch.id AS chapter_id,
                ch.transcript AS transcript_text
                , ch.processing_updated_at AS processing_update_ts
                , ch.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM chapter ch
                JOIN episodes e ON e.id = ch.episode_id
            """,
            "order_by": "e.id, ch.chapter_idx",
            "preprocessing_ts": "ch.preprocessing_updated_at",
            "processing_ts": "ch.processing_updated_at",
        }

    if step == "emotion_scoring":
        if level not in {None, "transcript_lines"}:
            raise ValueError(f"Unsupported level for emotion_scoring: {level}")
        return {
            "id_column": "tl.id",
            "select_sql": """
                tl.id AS transcript_line_id,
                tl.start_time AS start_time,
                tl.end_time AS end_time
                , tl.processing_updated_at AS processing_update_ts
                , tl.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM transcript_lines tl
            """,
            "order_by": "tl.chapter_id, tl.line_idx",
            "preprocessing_ts": "tl.preprocessing_updated_at",
            "processing_ts": "tl.processing_updated_at",
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
                    , ch.processing_updated_at AS processing_update_ts
                    , ch.preprocessing_updated_at AS preprocessing_update_ts
                """,
                "from_sql": """
                    FROM chapter ch
                """,
                "order_by": "ch.episode_id, ch.chapter_idx",
                "preprocessing_ts": "ch.preprocessing_updated_at",
                "processing_ts": "ch.processing_updated_at",
            }

        if level == "episode":
            return {
                "id_column": "e.id",
                "select_sql": """
                    e.id AS episode_id,
                    e.summary AS episode_summary
                    , e.processing_updated_at AS processing_update_ts
                    , e.preprocessing_updated_at AS preprocessing_update_ts
                """,
                "from_sql": """
                    FROM episodes e
                """,
                "order_by": "e.id",
                "preprocessing_ts": "e.preprocessing_updated_at",
                "processing_ts": "e.processing_updated_at",
            }

        return {
            "id_column": "p.id",
            "select_sql": """
                p.id AS podcast_id,
                p.title AS podcast_title
                , p.processing_updated_at AS processing_update_ts
                , p.preprocessing_updated_at AS preprocessing_update_ts
            """,
            "from_sql": """
                FROM podcasts p
            """,
            "order_by": "p.title, p.id",
            "preprocessing_ts": "p.preprocessing_updated_at",
            "processing_ts": "p.processing_updated_at",
        }

    raise ValueError(f"Unsupported fetch step: {step}")


def fetch_chunks(
    conn,
    step: str,
    level: Optional[str] = None,
    ids: Optional[Set[str]] = None,
    ctx: Optional[LoadContext] = None,
    end_ts: Optional[datetime] = None,
) -> List[Dict[str, Any]]:
    spec = _build_fetch_spec(step, level)

    where_parts: List[str] = []
    params: List[Any] = []

    if ids:
        where_parts.append(f"{spec['id_column']} = ANY(%s)")
        params.append(list(ids))

    if ctx is not None and ctx.mode == "delta" and ctx.watermark is not None:
        if end_ts is None:
            where_parts.append(f"({spec['preprocessing_ts']} > %s OR {spec['processing_ts']} IS NULL)")
            params.append(ctx.watermark)
        else:
            where_parts.append(
                f"(({spec['preprocessing_ts']} > %s AND {spec['preprocessing_ts']} <= %s) OR {spec['processing_ts']} IS NULL)"
            )
            params.extend([ctx.watermark, end_ts])

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
    # print("Executing SQL with params:", sql, params)

    chunks: List[Dict[str, Any]] = []
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        column_names = [column[0] for column in cur.description]

        for row in rows:
            chunk = dict(zip(column_names, row))
            _print_delta_debug(step, level, chunk, ctx, end_ts)
            chunks.append(chunk)

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
