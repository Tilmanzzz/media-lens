from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict


@dataclass(slots=True)
class TextSummarizerConfig:
    provider: str = "gemini"
    model: str = "gemini-2.5-flash-lite"
    temperature: float = 0.0
    default_input_path: str = "text_summarizer_test_input.json"
    default_output_path: str = "output_text_summarizer.json"
    default_mode: str = "both"
    logging_enabled: bool = False
    log_level: str = "INFO"
    log_dir: str = "../logs"
    log_file: str = "text_summarizer.log"
    llm_options: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_file(cls, config_path: str | Path) -> "TextSummarizerConfig":
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
            "provider": self.provider,
            "model": self.model,
            "temperature": self.temperature,
            "default_input_path": self.default_input_path,
            "default_output_path": self.default_output_path,
            "default_mode": self.default_mode,
            "logging_enabled": self.logging_enabled,
            "log_level": self.log_level,
            "log_dir": self.log_dir,
            "log_file": self.log_file,
            "llm_options": self.llm_options,
        }
