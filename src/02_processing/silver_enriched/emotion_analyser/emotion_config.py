from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Union

MODEL_ID = "superb/wav2vec2-base-superb-er"


@dataclass(slots=True)
class EmotionConfig:
    model_id: str = MODEL_ID
    cache_dir: str = "./hf_superb"
    sample_rate: int = 16000
    audio_dir: str = "./audio_test"
    test_files: List[str] = field(default_factory=lambda: ["angry_example.wav", "sad_example.wav", "happy_example.wav"])
    ffmpeg_binary: str = "ffmpeg"
    ffmpeg_audio_channels: int = 1
    ffmpeg_audio_rate: int = 16000
    logging_enabled: bool = False
    log_level: str = "INFO"
    log_dir: str = "../logs"
    log_file: str = "emotion_analyser.log"
    minio_bucket: str = "bronze"
    audio_cache_dir: str = "~/.audio_lens_cache/emotion_scoring"
    clear_cache_before_run: bool = False
    backend: str = "local"
    remote_endpoint_url: str = "http://100.120.90.32:8000/predict"
    remote_timeout: float = 30.0

    @classmethod
    def from_file(cls, config_path: str | Path) -> "EmotionConfig":
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

    def to_dict(self) -> Dict[str, Union[str, int, List[str], bool]]:
        return {
            "model_id": self.model_id,
            "cache_dir": self.cache_dir,
            "sample_rate": self.sample_rate,
            "audio_dir": self.audio_dir,
            "test_files": self.test_files,
            "ffmpeg_binary": self.ffmpeg_binary,
            "ffmpeg_audio_channels": self.ffmpeg_audio_channels,
            "ffmpeg_audio_rate": self.ffmpeg_audio_rate,
            "logging_enabled": self.logging_enabled,
            "log_level": self.log_level,
            "log_dir": self.log_dir,
            "log_file": self.log_file,
            "minio_bucket": self.minio_bucket,
            "audio_cache_dir": self.audio_cache_dir,
            "clear_cache_before_run": self.clear_cache_before_run,
            "backend": self.backend,
            "remote_endpoint_url": self.remote_endpoint_url,
            "remote_timeout": self.remote_timeout,
        }
