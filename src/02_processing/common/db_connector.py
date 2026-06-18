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


if __name__ == "__main__":
    connector = DbConnector()
    with connector.get_connection() as conn:
        print("Connected to database successfully.")