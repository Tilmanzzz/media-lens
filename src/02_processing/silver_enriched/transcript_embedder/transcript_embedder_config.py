from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Optional


@dataclass(slots=True)
class TranscriptEmbedderConfig:
    provider: str = "ollama"
    model: str = "qwen3-embedding:4b"
    dimension: Optional[int] = 2560
    task_instruction: str = "Represent this podcast transcript segment for semantic retrieval:"
    input_text_field: str = "transcription"
    batch_size: int = 32
    max_podcast_sample_size: int = 5
    default_input_path: str = "test/transcript_embedder_test_input.json"
    default_output_path: str = "test/embedded_output.json"
    default_mode: str = "all"
    logging_enabled: bool = True
    log_level: str = "INFO"
    log_dir: str = "../logs"
    log_file: str = "transcript_embedder.log"
    embed_options: Dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_file(cls, config_path: str | Path) -> "TranscriptEmbedderConfig":
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
            "dimension": self.dimension,
            "task_instruction": self.task_instruction,
            "input_text_field": self.input_text_field,
            "batch_size": self.batch_size,
            "max_podcast_sample_size": self.max_podcast_sample_size,
            "default_input_path": self.default_input_path,
            "default_output_path": self.default_output_path,
            "default_mode": self.default_mode,
            "logging_enabled": self.logging_enabled,
            "log_level": self.log_level,
            "log_dir": self.log_dir,
            "log_file": self.log_file,
            "embed_options": self.embed_options,
        }
