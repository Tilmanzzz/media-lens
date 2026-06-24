from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Union

import requests

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src/02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))


from common.app_logger import AppLogger

from .emotion_config import EmotionConfig
from .emotion_label_catalog import EmotionLabelCatalog, _normalize_label


class RemoteEmotionEndpointUnavailable(RuntimeError):
    """Raised when the remote emotion backend can't be reached at all (vs. a
    single bad request/response), so callers can fail the whole run instead of
    skipping line by line."""


class EmotionAnalyser:
    def __init__(
        self,
        config: Optional[EmotionConfig] = None,
        config_path: Optional[str | Path] = None,
    ) -> None:
        if config is None and config_path is None:
            config_path = Path(__file__).resolve().with_name("emotion_analyser_config.json")

        if config is None and config_path is not None:
            config = EmotionConfig.from_file(config_path)

        self.config = config or EmotionConfig()
        self._base_dir = Path(__file__).resolve().parent

        self.audio_dir = Path(self.config.audio_dir)
        if not self.audio_dir.is_absolute():
            self.audio_dir = self._base_dir / self.audio_dir

        cache_dir = Path(self.config.cache_dir)
        if not cache_dir.is_absolute():
            cache_dir = self._base_dir / cache_dir

        self.cache_dir = cache_dir
        self._setup_logger()

        self.backend = (self.config.backend or "local").strip().lower()
        if self.backend not in ("local", "remote"):
            raise ValueError(
                f"Unsupported emotion backend: {self.config.backend!r}. Use 'local' or 'remote'."
            )

        self.model = None
        self.feature_extractor = None
        self.emotion_catalog = None

        if self.backend == "local":
            self.logger.info("Loading emotion model: %s", self.config.model_id)
            from transformers import (Wav2Vec2FeatureExtractor,
                                      Wav2Vec2ForSequenceClassification)

            self.model = Wav2Vec2ForSequenceClassification.from_pretrained(
                self.config.model_id,
                cache_dir=str(self.cache_dir),
            )
            self.feature_extractor = Wav2Vec2FeatureExtractor.from_pretrained(
                self.config.model_id,
                cache_dir=str(self.cache_dir),
            )
            self.emotion_catalog = EmotionLabelCatalog.from_model(self.model)
            self.model.eval()
            self.logger.info("Emotion model loaded successfully")
        else:
            self.logger.info("Using remote emotion endpoint: %s", self.config.remote_endpoint_url)

    def _setup_logger(self) -> None:
        log_dir = Path(self.config.log_dir)
        if not log_dir.is_absolute():
            log_dir = self._base_dir / log_dir

        self.logger = AppLogger(
            module_name="emotion_analyser",
            enabled=self.config.logging_enabled,
            level=self.config.log_level,
            log_dir=log_dir,
            log_file=self.config.log_file,
        ).build()

    def available_emotions(self) -> List[Dict[str, Union[int, str]]]:
        if self.emotion_catalog is None:
            raise RuntimeError("available_emotions() requires backend='local'")
        self.logger.debug("Returning %d available emotion labels", len(self.emotion_catalog.as_list()))
        return self.emotion_catalog.as_list()

    def _convert_m4a_to_wav(self, input_path: Path) -> Path:
        output_path = input_path.with_suffix(".wav")
        self.logger.info("Converting audio to wav: %s", input_path)
        cmd = [
            self.config.ffmpeg_binary,
            "-y",
            "-i",
            str(input_path),
            "-ac",
            str(self.config.ffmpeg_audio_channels),
            "-ar",
            str(self.config.ffmpeg_audio_rate),
            str(output_path),
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            self.logger.info("Conversion complete: %s", output_path)
        except FileNotFoundError as exc:
            self.logger.exception("ffmpeg not available")
            raise RuntimeError("ffmpeg is not installed or not available in PATH.") from exc
        except subprocess.CalledProcessError as exc:
            self.logger.exception("ffmpeg conversion failed")
            raise RuntimeError(f"ffmpeg conversion failed: {exc.stderr}") from exc

        return output_path

    def prepare_audio(self, path: Union[str, Path]) -> Path:
        audio_path = Path(path)
        if not audio_path.is_absolute() and not audio_path.exists():
            audio_path = self.audio_dir / audio_path

        if not audio_path.exists():
            self.logger.error("Audio file not found: %s", audio_path)
            raise FileNotFoundError(f"Audio file not found: {audio_path.resolve()}")

        suffix = audio_path.suffix.lower()
        if suffix == ".wav":
            self.logger.debug("Using wav input: %s", audio_path)
            return audio_path
        if suffix == ".m4a":
            return self._convert_m4a_to_wav(audio_path)

        self.logger.error("Unsupported audio format: %s", suffix)
        raise ValueError(f"Unsupported audio format '{suffix}'. Use .wav or .m4a")

    # Wav2Vec2's first conv layer has kernel_size=10; require at least 400 samples
    _MIN_SAMPLES = 400

    def score_audio(
        self,
        path: Union[str, Path],
        start_time: Optional[float] = None,
        end_time: Optional[float] = None,
        source_audio_key: Optional[str] = None,
    ) -> Dict[str, Union[str, int, float]]:
        self.logger.info(
            "Scoring audio file: %s start=%s end=%s source_audio_key=%s",
            path, start_time, end_time, source_audio_key,
        )
        wav_path = self.prepare_audio(path)

        if self.backend == "remote":
            return self._score_audio_remote(wav_path)
        return self._score_audio_local(wav_path)

    def _score_audio_local(self, wav_path: Path) -> Dict[str, Union[str, int, float]]:
        import librosa
        import torch

        speech_array, _ = librosa.load(str(wav_path), sr=self.config.sample_rate)

        if len(speech_array) < self._MIN_SAMPLES:
            raise ValueError(
                f"Audio segment too short for emotion scoring: {len(speech_array)} samples "
                f"(minimum {self._MIN_SAMPLES}). File: {wav_path}"
            )

        inputs = self.feature_extractor(
            speech_array,
            sampling_rate=self.config.sample_rate,
            return_tensors="pt",
            padding=True,
        )

        with torch.no_grad():
            logits = self.model(**inputs).logits

        probs = torch.softmax(logits, dim=-1)
        best_id = int(torch.argmax(probs, dim=-1).item())
        confidence = float(probs[0][best_id].item())
        label = self.emotion_catalog.get_label(best_id)

        return {
            "file": str(wav_path),
            "emotion": str(label),
            "emotionId": best_id,
            "confidence": confidence,
        }

    def _score_audio_remote(self, wav_path: Path) -> Dict[str, Union[str, int, float]]:
        self.logger.debug("Scoring via remote endpoint: %s", self.config.remote_endpoint_url)
        try:
            with wav_path.open("rb") as handle:
                response = requests.post(
                    self.config.remote_endpoint_url,
                    files={"file": (wav_path.name, handle, "audio/wav")},
                    timeout=self.config.remote_timeout,
                )
            response.raise_for_status()
            payload = response.json()
        except (requests.ConnectionError, requests.Timeout) as exc:
            raise RemoteEmotionEndpointUnavailable(
                f"Remote emotion endpoint unreachable ({self.config.remote_endpoint_url}): {exc}"
            ) from exc
        except requests.RequestException as exc:
            raise RuntimeError(f"Remote emotion endpoint request failed: {exc}") from exc

        # Expected shape: {"predictions": [{"label": "ang", "emotion": "angry", "score": 0.91}, ...],
        # "top": {"label": "ang", "emotion": "angry", "score": 0.91}}
        best = payload.get("top") if isinstance(payload, dict) else None
        if not isinstance(best, dict):
            predictions = payload.get("predictions") if isinstance(payload, dict) else None
            if not isinstance(predictions, list) or not predictions:
                raise RuntimeError(f"Remote emotion endpoint returned no predictions: {payload!r}")
            best = max(predictions, key=lambda item: float(item.get("score", 0.0)))

        label = _normalize_label(best.get("emotion") or best.get("label"))
        confidence = float(best.get("score", 0.0))

        return {
            "file": str(wav_path),
            "emotion": label,
            "emotionId": None,
            "confidence": confidence,
        }