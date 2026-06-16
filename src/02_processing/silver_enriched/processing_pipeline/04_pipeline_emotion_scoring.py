from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, DefaultDict, Dict, Iterable, List, Optional

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src\\02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))
from common.app_logger import AppLogger
from common.db_connector import DbConnector
from minio.error import S3Error
from silver_enriched.emotion_analyser.emotion_analyser import EmotionAnalyser
from silver_enriched.emotion_analyser.minio_utils import (
    download_object_to_path, init_minio_client)
from silver_enriched.processing_pipeline.pipeline_utils import (
    LoadContext, build_pipeline_logger, fetch_chunks, load_json_config,
    pipeline_batch_scope)


def parse_args() -> argparse.Namespace:
    pre_parser = argparse.ArgumentParser(add_help=False)
    pre_parser.add_argument("--config", default=None, help="Path to pipeline args JSON config")
    pre_args, remaining = pre_parser.parse_known_args()

    parser = argparse.ArgumentParser(description="Run emotion scoring against transcript lines (full or delta).")
    parser.add_argument("--config", default="processing_pipeline_config.json", help="Path to pipeline args JSON config")
    parser.add_argument("--mode", choices=["full", "delta"], default="delta")
    parser.add_argument("--stage", default="emotion_scoring", help="pipeline_batches.stage tag (documentation only)")
    parser.add_argument("--batch-id", default=None, help="Batch UUID to store on writes")
    parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Run without database writes",
    )
    parser.add_argument(
        "--log-enabled",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Enable pipeline logging",
    )
    parser.add_argument("--log-level", default="INFO", help="Pipeline logger level")
    parser.add_argument("--log-dir", default=None, help="Optional pipeline log directory")
    parser.add_argument("--log-file", default="emotion_scoring_pipeline.log", help="Pipeline log file name")
    parser.add_argument("--cache-dir", default=None, help="Optional persistent cache directory for episode audio files")

    config = load_json_config(pre_args.config or parser.get_default("config"), base_dir=Path(__file__).resolve().parent)
    if config:
        parser.set_defaults(**config)

    return parser.parse_args(remaining)





def _extract_line_segment(
    source_audio: Path,
    target_audio: Path,
    start_time: float,
    end_time: float,
    logger=None,
) -> Path:
    duration = max(0.0, float(end_time) - float(start_time))
    if duration <= 0:
        raise ValueError(f"Invalid transcript line duration: start={start_time} end={end_time}")

    cmd = [
        "ffmpeg",
        "-y",
        "-ss",
        str(float(start_time)),
        "-i",
        str(source_audio),
        "-t",
        str(duration),
        "-ac",
        "1",
        "-ar",
        "16000",
        str(target_audio),
    ]

    if logger is not None:
        logger.debug("ffmpeg extract start: %s", " ".join(cmd))

    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise RuntimeError("ffmpeg is not installed or not available in PATH.") from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"ffmpeg segment extraction failed: {exc.stderr}") from exc

    return target_audio


def _group_by_episode(chunks: Iterable[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    grouped: DefaultDict[str, List[Dict[str, Any]]] = defaultdict(list)
    for chunk in chunks:
        episode_id = chunk.get("episode_id")
        if not episode_id:
            continue
        grouped[str(episode_id)].append(chunk)
    return dict(grouped)


def _update_transcript_lines(
    conn,
    rows: Iterable[Dict[str, Any]],
    batch_id: Optional[str],
    processing_update_ts: Optional[datetime],
    logger=None,
) -> int:
    if processing_update_ts is None:
        raise ValueError("processing_update_ts is required for processing writes")

    params: List[tuple] = []
    for row in rows:
        line_id = row.get("transcript_line_id")
        emotion = row.get("emotion")
        emotion_score = row.get("emotion_score")
        if not line_id or emotion is None or emotion_score is None:
            continue

        params.append((str(emotion), float(emotion_score), batch_id, processing_update_ts, line_id))

    if logger is not None:
        logger.info("DB write start: transcript_lines count=%d batch_id=%s", len(params), batch_id or "-")

    sql = """
        UPDATE transcript_lines
        SET emotion = %s::emotion_label,
            emotion_score = %s,
            batch_id = %s,
            processing_updated_at = %s
        WHERE id = %s
    """

    with conn.cursor() as cur:
        if params:
            cur.executemany(sql, params)

    if logger is not None:
        logger.info("DB write done: transcript_lines rows=%d", len(params))

    return len(params)


def run_step(conn, ctx: LoadContext, args: argparse.Namespace) -> None:
    logger = ctx.logger or build_pipeline_logger(
        module_name="emotion_scoring_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    )

    dry_run = args.dry_run or ctx.dry_run
    with pipeline_batch_scope(conn, args.stage, ctx.mode, args.batch_id, dry_run, logger=logger) as batch_id:
        chunks = fetch_chunks(
            conn,
            step="emotion_scoring",
            level="transcript_lines",
            ctx=ctx,
            logger=logger,
        )
        if not chunks:
            logger.warning("emotion_scoring: no chunks")
            return

        logger.info("emotion_scoring: chunks=%d", len(chunks))
        if logger is not None:
            try:
                logger.debug("emotion_scoring: sample_chunks=%s", str(chunks[:5]))
            except Exception:
                logger.debug("emotion_scoring: sample_chunks unavailable")

        minio_client = init_minio_client()
        analyser = EmotionAnalyser()

        # persistent per-episode cache (configurable via --cache-dir, EMOTION_CACHE_DIR, or emotion_analyser_config.json)
        cache_dir_arg = args.cache_dir or os.environ.get("EMOTION_CACHE_DIR") or analyser.config.audio_cache_dir
        cache_root = Path(cache_dir_arg).expanduser()
        try:
            cache_root.mkdir(parents=True, exist_ok=True)
        except Exception:
            # fallback to temp dir if cache cannot be created
            cache_root = None

        if cache_root is not None and analyser.config.clear_cache_before_run:
            logger.info("emotion_scoring: clearing audio cache dir=%s", str(cache_root))
            for cached_file in cache_root.iterdir():
                if cached_file.is_file():
                    cached_file.unlink()

        with tempfile.TemporaryDirectory(prefix="emotion_scoring_") as temp_dir:
            temp_root = Path(temp_dir)
            local_audio_cache: Dict[str, Path] = {}
            updates: List[Dict[str, Any]] = []

            for episode_id, episode_chunks in _group_by_episode(chunks).items():
                audio_key = str(episode_chunks[0].get("audio_key") or "").strip()
                if not audio_key:
                    logger.warning("emotion_scoring: missing audio_key episode_id=%s", episode_id)
                    continue

                source_audio = local_audio_cache.get(audio_key)
                if source_audio is None:
                    filename = Path(audio_key).name
                    try:
                        if cache_root is not None:
                            cached_path = cache_root / filename
                            if not cached_path.exists():
                                logger.info("emotion_scoring: downloading audio_key=%s to cache=%s", audio_key, str(cached_path))
                                download_object_to_path(minio_client, audio_key, cached_path, logger=logger)
                                try:
                                    logger.info("emotion_scoring: downloaded size=%d", cached_path.stat().st_size)
                                except Exception:
                                    logger.debug("emotion_scoring: could not stat cached file")
                            else:
                                logger.info("emotion_scoring: using cached audio file=%s", str(cached_path))
                            source_audio = cached_path
                        else:
                            # fallback to ephemeral temp root
                            source_audio = temp_root / filename
                            logger.info("emotion_scoring: downloading audio_key=%s to temp=%s", audio_key, str(source_audio))
                            download_object_to_path(minio_client, audio_key, source_audio, logger=logger)
                            try:
                                logger.info("emotion_scoring: downloaded size=%d", source_audio.stat().st_size)
                            except Exception:
                                logger.debug("emotion_scoring: could not stat temp file")
                    except S3Error as exc:
                        if exc.code == "NoSuchKey":
                            logger.error(
                                "emotion_scoring: audio object missing, skipping episode episode_id=%s audio_key=%s: %s",
                                episode_id, audio_key, exc,
                            )
                            continue
                        raise
                    local_audio_cache[audio_key] = source_audio

                for chunk in episode_chunks:
                    line_id = chunk.get("transcript_line_id")
                    start_time = chunk.get("start_time")
                    end_time = chunk.get("end_time")
                    if not line_id or start_time is None or end_time is None:
                        logger.debug(
                            "emotion_scoring: skipping chunk missing fields line_id=%s start_time=%s end_time=%s chunk=%s",
                            line_id,
                            start_time,
                            end_time,
                            str(chunk),
                        )
                        continue

                    segment_path = temp_root / f"{line_id}.wav"
                    try:
                        logger.debug("emotion_scoring: extracting segment line_id=%s start=%s end=%s to %s", line_id, start_time, end_time, str(segment_path))
                        _extract_line_segment(source_audio, segment_path, float(start_time), float(end_time), logger=logger)
                        logger.debug("emotion_scoring: extracting done line_id=%s", line_id)
                        result = analyser.score_audio(segment_path)
                        logger.debug("emotion_scoring: analyser result for line_id=%s -> %s", line_id, str(result))
                    except Exception as exc:
                        logger.exception("emotion_scoring: failed transcript_line_id=%s: %s", line_id, exc)
                        continue

                    updates.append({
                        "transcript_line_id": line_id,
                        "emotion": result.get("emotion"),
                        "emotion_score": result.get("confidence"),
                    })
                    logger.debug("emotion_scoring: appended update for line_id=%s emotion=%s score=%s", line_id, result.get("emotion"), result.get("confidence"))

        if not updates:
            logger.warning("emotion_scoring: no successful updates")
            return

        if dry_run:
            logger.info("emotion_scoring: dry run, skip writes")
            return

        total_updates = _update_transcript_lines(
            conn,
            updates,
            batch_id,
            ctx.processing_update_ts,
            logger=logger,
        )
        logger.info("DB commit start: emotion_scoring rows=%d", total_updates)
        conn.commit()
        logger.info("DB commit done: emotion_scoring rows=%d", total_updates)
        logger.info("emotion_scoring: done rows=%d", total_updates)


def main() -> None:
    args = parse_args()
    connector = DbConnector()

    logger = AppLogger(
        module_name="emotion_scoring_pipeline",
        enabled=args.log_enabled,
        level=args.log_level,
        log_dir=args.log_dir,
        log_file=args.log_file,
    ).build()

    with connector.get_connection(logger=logger) as conn:
        ctx = LoadContext(
            mode=args.mode,
            connector=connector,
            processing_update_ts=datetime.now(timezone.utc),
            logger=logger,
            dry_run=args.dry_run,
        )

        run_step(conn, ctx, args)


if __name__ == "__main__":
    main()