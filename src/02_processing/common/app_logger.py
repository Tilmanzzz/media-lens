from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional


class App_Logger:
    def __init__(
        self,
        module_name: str,
        enabled: bool = False,
        level: str = "INFO",
        log_dir: Optional[str | Path] = None,
        log_file: Optional[str] = None,
    ) -> None:
        self.module_name = module_name
        self.enabled = enabled
        self.level = getattr(logging, str(level).upper(), logging.INFO)

        default_dir = Path(__file__).resolve().parents[1] / "logs"
        self.log_dir = Path(log_dir) if log_dir else default_dir
        self.log_file = log_file or f"{module_name}.log"

    def build(self) -> logging.Logger:
        logger = logging.getLogger(self.module_name)
        logger.propagate = False

        # Reset handlers so repeated initialization updates config cleanly.
        for handler in list(logger.handlers):
            logger.removeHandler(handler)
            try:
                handler.close()
            except Exception:
                pass

        if self.enabled:
            self.log_dir.mkdir(parents=True, exist_ok=True)

            formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s")

            stream_handler = logging.StreamHandler()
            stream_handler.setFormatter(formatter)
            logger.addHandler(stream_handler)

            file_handler = logging.FileHandler(self.log_dir / self.log_file, encoding="utf-8")
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)

            logger.setLevel(self.level)
            logger.disabled = False
        else:
            logger.setLevel(logging.CRITICAL)
            logger.disabled = True

        return logger


AppLogger = App_Logger


def child_logger(parent: logging.Logger, name: str) -> logging.Logger:
    child = logging.getLogger(f"{parent.name}.{name}")
    child.setLevel(parent.level)
    child.handlers.clear()
    child.propagate = True
    return child
