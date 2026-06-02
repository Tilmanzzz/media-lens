from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any, Optional

import psycopg
import sys
from pathlib import Path

SRC_DIR = str(Path(__file__).resolve()).split("src")[0]
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))
    
from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parents[3] / ".env")

class DbConnector:
    def __init__(self, postgres_url: Optional[str] = None) -> None:
        self.postgres_url = postgres_url or os.environ.get("POSTGRES_URL")
        if not self.postgres_url:
            raise RuntimeError("POSTGRES_URL is not set")

    def get_connection(self, logger: Optional[Any] = None) -> psycopg.Connection:
        if logger is not None:
            logger.info("DB connection start")
        connection = psycopg.connect(self.postgres_url)
        if logger is not None:
            logger.info("DB connection opened")
        return connection

    @staticmethod
    def parse_ts(value: object) -> Optional[datetime]:
        if value is None:
            return None
        if isinstance(value, datetime):
            return value
        if isinstance(value, (int, float)):
            return datetime.fromtimestamp(value, tz=timezone.utc)
        if isinstance(value, str):
            clean = value.strip()
            if clean.endswith("Z"):
                clean = clean[:-1] + "+00:00"
            try:
                return datetime.fromisoformat(clean)
            except ValueError:
                return None
        return None

    def get_watermark(self, conn: psycopg.Connection, stage: str, logger: Optional[Any] = None) -> datetime:
        sql = (
            "SELECT COALESCE(MAX(fin_ts), TIMESTAMPTZ '1970-01-01') "
            "FROM pipeline_batches WHERE stage = %s AND status = 'success'"
        )
        if logger is not None:
            logger.info("DB query start: watermark stage=%s", stage)
        with conn.cursor() as cur:
            cur.execute(sql, (stage,))
            row = cur.fetchone()
        watermark = datetime(1970, 1, 1, tzinfo=timezone.utc)
        if row and row[0] is not None:
            watermark = self.parse_ts(row[0]) or watermark
        if logger is not None:
            logger.info("DB query done: watermark stage=%s value=%s", stage, watermark)
        return watermark


if __name__ == "__main__":
    connector = DbConnector()
    with connector.get_connection() as conn:
        print("Connected to database successfully.")
        watermark = connector.get_watermark(conn, "processing")
        print("Current watermark for processing:", watermark)