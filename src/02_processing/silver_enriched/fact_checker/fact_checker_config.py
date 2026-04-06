from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List

DEFAULT_ALLOWED_VERDICTS = [
    "TRUE",
    "MOSTLY_TRUE",
    "MISLEADING",
    "FALSE",
    "UNVERIFIABLE",
]


@dataclass(slots=True)
class FactCheckerConfig:
    model: str = "gemma3:4b"
    temperature: float = 0.0
    region: str = "us-en"
    max_queries_per_claim: int = 3
    max_search_results_per_query: int = 2
    max_sources_per_claim: int = 5
    logging_enabled: bool = False
    log_level: str = "INFO"
    log_dir: str = "../logs"
    log_file: str = "fact_checker.log"
    allowed_verdicts: List[str] = field(default_factory=lambda: list(DEFAULT_ALLOWED_VERDICTS))
    llm_options: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_file(cls, config_path: str | Path) -> "FactCheckerConfig":
        raw_path = Path(config_path).expanduser()

        if raw_path.is_absolute():
            candidate_paths = [raw_path]
        else:
            module_dir = Path(__file__).resolve().parent
            candidate_paths = [Path.cwd() / raw_path, module_dir / raw_path]

        path = next((p for p in candidate_paths if p.exists()), None)
        if path is None:
            tried_paths = ", ".join(str(p) for p in candidate_paths)
            raise FileNotFoundError(f"Config file not found. Tried: {tried_paths}")

        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        return cls(**data)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "model": self.model,
            "temperature": self.temperature,
            "region": self.region,
            "max_queries_per_claim": self.max_queries_per_claim,
            "max_search_results_per_query": self.max_search_results_per_query,
            "max_sources_per_claim": self.max_sources_per_claim,
            "logging_enabled": self.logging_enabled,
            "log_level": self.log_level,
            "log_dir": self.log_dir,
            "log_file": self.log_file,
            "allowed_verdicts": self.allowed_verdicts,
            "llm_options": self.llm_options,
        }
