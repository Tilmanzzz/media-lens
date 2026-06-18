from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from minio import Minio

from .emotion_config import EmotionConfig

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src/02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

load_dotenv(Path(__file__).resolve().parents[3] / ".env")

def init_minio_client(config: Optional[EmotionConfig] = None) -> Minio:
    """Create and return a MinIO client using env vars or EmotionConfig defaults."""
    if config is None:
        cfg_path = Path(__file__).resolve().with_name("emotion_analyser_config.json")
        try:
            config = EmotionConfig.from_file(cfg_path)
        except Exception:
            config = EmotionConfig()

    endpoint = os.getenv("MINIO_ENDPOINT", "localhost:9000").replace("http://", "").replace("https://", "")
    user = os.getenv("MINIO_USER")
    password = os.getenv("MINIO_PASS")
    secure = os.getenv("MINIO_SECURE", "false").lower() in ("1", "true", "yes")

    return Minio(endpoint, access_key=user, secret_key=password, secure=secure)


def download_object_to_path(
    minio_client: Minio,
    object_name: str,
    target_path: Path,
    bucket: Optional[str] = None,
    config: Optional[EmotionConfig] = None,
    logger=None,
) -> Path:
    """Download `object_name` from MinIO into `target_path`.

    The bucket name is taken from `bucket` if provided, otherwise from the EmotionConfig
    `minio_bucket` value. If neither is available, falls back to "bronze".
    """
    if config is None:
        cfg_path = Path(__file__).resolve().with_name("emotion_analyser_config.json")
        try:
            config = EmotionConfig.from_file(cfg_path)
        except Exception:
            config = EmotionConfig()

    bucket_name = bucket or getattr(config, "minio_bucket", None) or "bronze"

    if logger is not None:
        logger.info("MinIO download start: bucket=%s object=%s target=%s", bucket_name, object_name, target_path)

    response = minio_client.get_object(bucket_name, object_name)
    try:
        with target_path.open("wb") as handle:
            for chunk in response.stream(32 * 1024):
                handle.write(chunk)
    finally:
        response.close()
        response.release_conn()

    if logger is not None:
        logger.info("MinIO download done: bucket=%s object=%s target=%s", bucket_name, object_name, target_path)

    return target_path


