from __future__ import annotations

import os
import random
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import ollama
from dotenv import load_dotenv

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src/02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

load_dotenv(Path(__file__).resolve().parents[3] / ".env")

from common.app_logger import AppLogger

from .transcript_embedder_config import TranscriptEmbedderConfig


class TranscriptEmbedder:
    def __init__(
        self,
        config: Optional[TranscriptEmbedderConfig] = None,
        config_path: Optional[str | Path] = None,
        logging_enabled: Optional[bool] = None,
        log_level: Optional[str] = None,
    ) -> None:
        if config is None and config_path is not None:
            config = TranscriptEmbedderConfig.from_file(config_path)
        if config is None:
            default_path = Path(__file__).resolve().parent / "transcript_embedder_config.json"
            if default_path.exists():
                config = TranscriptEmbedderConfig.from_file(default_path)
        self.config = config or TranscriptEmbedderConfig()
        self._setup_logger(logging_enabled=logging_enabled, log_level=log_level)

        if self.config.batch_size <= 0:
            raise ValueError("batch_size must be greater than 0")
        if self.config.max_podcast_sample_size <= 0:
            raise ValueError("max_podcast_sample_size must be greater than 0")

        self._gemini_embeddings = self._build_gemini_embeddings()

    def _build_gemini_embeddings(self):
        provider = (self.config.provider or "ollama").strip().lower()
        if provider != "gemini":
            return None

        try:
            from langchain_google_genai import \
                GoogleGenerativeAIEmbeddings  # type: ignore[import-not-found]
        except ImportError as exc:
            raise ImportError("Missing dependency: langchain-google-genai") from exc

        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY is not set in the environment")

        return GoogleGenerativeAIEmbeddings(
            model=self.config.model,
            google_api_key=api_key,
            output_dimensionality=self.config.dimension,
            **self.config.embed_options,
        )

    def _setup_logger(self, logging_enabled: Optional[bool], log_level: Optional[str]) -> None:
        enabled = self.config.logging_enabled if logging_enabled is None else logging_enabled
        level_name = log_level or self.config.log_level or "INFO"

        log_dir = Path(self.config.log_dir)
        if not log_dir.is_absolute():
            log_dir = Path(__file__).resolve().parent / log_dir

        self.logger = AppLogger(
            module_name="transcript_embedder",
            enabled=enabled,
            level=level_name,
            log_dir=log_dir,
            log_file=self.config.log_file,
        ).build()

    @staticmethod
    def _group_by_episode(chunks: List[Dict[str, Any]]) -> Dict[Tuple[Any, Any], List[Dict[str, Any]]]:
        grouped: Dict[Tuple[Any, Any], List[Dict[str, Any]]] = defaultdict(list)
        for chunk in chunks:
            grouped[(chunk.get("podcast_id"), chunk.get("episode_id"))].append(chunk)
        return grouped

    @staticmethod
    def _group_by_segment(chunks: List[Dict[str, Any]]) -> Dict[Tuple[Any, Any, Any], List[Dict[str, Any]]]:
        grouped: Dict[Tuple[Any, Any, Any], List[Dict[str, Any]]] = defaultdict(list)
        for chunk in chunks:
            grouped[(chunk.get("podcast_id"), chunk.get("episode_id"), chunk.get("segment_id"))].append(chunk)
        return grouped

    @staticmethod
    def _group_by_podcast(chunks: List[Dict[str, Any]]) -> Dict[Any, List[Dict[str, Any]]]:
        grouped: Dict[Any, List[Dict[str, Any]]] = defaultdict(list)
        for chunk in chunks:
            grouped[chunk.get("podcast_id")].append(chunk)
        return grouped

    @staticmethod
    def _sort_chunks(chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        return sorted(
            chunks,
            key=lambda item: (
                str(item.get("segment_id", "")),
                str(item.get("chunk_id", "")),
            ),
        )

    def _get_text(self, chunk: Dict[str, Any]) -> str:
        text = chunk.get(self.config.input_text_field)
        if text is None and self.config.input_text_field != "transcript_text":
            text = chunk.get("transcript_text")
        if text is None and self.config.input_text_field != "transcription":
            text = chunk.get("transcription")
        return str(text or "").strip()

    def _prompted_text(self, text: str) -> str:
        return f"{self.config.task_instruction} {text}".strip()

    def _embed_batch_ollama(self, batch: List[str]) -> List[List[float]]:
        response = ollama.embed(
            model=self.config.model,
            input=batch,
            **self.config.embed_options,
        )
        embeddings = getattr(response, "embeddings", None)
        if embeddings is None:
            embeddings = response["embeddings"]
        return embeddings

    def _embed_batch_gemini(self, batch: List[str]) -> List[List[float]]:
        return self._gemini_embeddings.embed_documents(batch)

    def _embed_texts(self, texts: List[str]) -> List[List[float]]:
        if not texts:
            return []

        provider = (self.config.provider or "ollama").strip().lower()
        embeddings_out: List[List[float]] = []
        for start in range(0, len(texts), self.config.batch_size):
            batch = texts[start : start + self.config.batch_size]
            if provider == "gemini":
                embeddings_out.extend(self._embed_batch_gemini(batch))
            else:
                embeddings_out.extend(self._embed_batch_ollama(batch))

        if len(embeddings_out) != len(texts):
            raise RuntimeError("Embedding count mismatch between input texts and output vectors")

        if self.config.dimension and embeddings_out:
            actual_dim = len(embeddings_out[0])
            if actual_dim != self.config.dimension:
                raise ValueError(
                    f"Embedding dimension mismatch: configured dimension={self.config.dimension}, "
                    f"model={self.config.model} returned {actual_dim}"
                )

        return embeddings_out

    def embed_chunks(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        valid_chunks = [chunk for chunk in chunks if self._get_text(chunk)]
        self.logger.info("Embedding %d chunks", len(valid_chunks))

        texts = [self._prompted_text(self._get_text(chunk)) for chunk in valid_chunks]
        vectors = self._embed_texts(texts)

        return [
            {
                **chunk,
                "embedding": embedding,
                "embedding_model": self.config.model,
                "embedding_level": "chunk",
            }
            for chunk, embedding in zip(valid_chunks, vectors)
        ]

    def embed_episodes(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        grouped = self._group_by_episode(chunks)
        records: List[Dict[str, Any]] = []

        for (podcast_id, episode_id), episode_chunks in grouped.items():
            ordered = self._sort_chunks(episode_chunks)
            text = "\n\n".join(self._get_text(chunk) for chunk in ordered if self._get_text(chunk))
            if not text:
                continue

            records.append(
                {
                    "podcast_id": podcast_id,
                    "podcast_title": ordered[0].get("podcast_title", "") if ordered else "",
                    "episode_id": episode_id,
                    "episode_title": ordered[0].get("episode_title", "") if ordered else "",
                    "source_chunk_count": len(ordered),
                    "text": text,
                }
            )

        self.logger.info("Embedding %d episodes", len(records))
        vectors = self._embed_texts([self._prompted_text(record["text"]) for record in records])

        return [
            {
                "podcast_id": record["podcast_id"],
                "podcast_title": record["podcast_title"],
                "episode_id": record["episode_id"],
                "episode_title": record["episode_title"],
                "source_chunk_count": record["source_chunk_count"],
                "embedding": embedding,
                "embedding_model": self.config.model,
                "embedding_level": "episode",
            }
            for record, embedding in zip(records, vectors)
        ]

    def embed_segments(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        grouped = self._group_by_segment(chunks)
        records: List[Dict[str, Any]] = []

        for (podcast_id, episode_id, segment_id), segment_chunks in grouped.items():
            ordered = self._sort_chunks(segment_chunks)
            text = "\n\n".join(self._get_text(chunk) for chunk in ordered if self._get_text(chunk))
            if not text:
                continue

            records.append(
                {
                    "podcast_id": podcast_id,
                    "podcast_title": ordered[0].get("podcast_title", "") if ordered else "",
                    "episode_id": episode_id,
                    "episode_title": ordered[0].get("episode_title", "") if ordered else "",
                    "segment_id": segment_id,
                    "source_chunk_count": len(ordered),
                    "text": text,
                }
            )

        self.logger.info("Embedding %d segments", len(records))
        vectors = self._embed_texts([self._prompted_text(record["text"]) for record in records])

        return [
            {
                "podcast_id": record["podcast_id"],
                "podcast_title": record["podcast_title"],
                "episode_id": record["episode_id"],
                "episode_title": record["episode_title"],
                "segment_id": record["segment_id"],
                "source_chunk_count": record["source_chunk_count"],
                "embedding": embedding,
                "embedding_model": self.config.model,
                "embedding_level": "segment",
            }
            for record, embedding in zip(records, vectors)
        ]

    def embed_podcasts(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        grouped = self._group_by_podcast(chunks)
        records: List[Dict[str, Any]] = []

        available_podcast_ids = list(grouped.keys())
        selected_count = min(self.config.max_podcast_sample_size, len(available_podcast_ids))
        if len(available_podcast_ids) > selected_count:
            selected_podcast_ids = random.sample(available_podcast_ids, selected_count)
        else:
            selected_podcast_ids = available_podcast_ids

        self.logger.info(
            "Selecting %d of %d podcasts for podcast-level embedding",
            len(selected_podcast_ids),
            len(available_podcast_ids),
        )

        for podcast_id in selected_podcast_ids:
            podcast_items = grouped[podcast_id]
            ordered = sorted(podcast_items, key=lambda item: str(item.get("episode_id", "")))
            text = "\n\n".join(self._get_text(item) for item in ordered if self._get_text(item))
            if not text:
                continue

            episode_ids = sorted({str(item.get("episode_id", "")) for item in ordered if item.get("episode_id") is not None})
            records.append(
                {
                    "podcast_id": podcast_id,
                    "podcast_title": ordered[0].get("podcast_title", "") if ordered else "",
                    "source_episode_count": len(episode_ids),
                    "source_episode_ids": episode_ids,
                    "text": text,
                }
            )

        self.logger.info("Embedding %d podcasts", len(records))
        vectors = self._embed_texts([self._prompted_text(record["text"]) for record in records])

        return [
            {
                "podcast_id": record["podcast_id"],
                "podcast_title": record["podcast_title"],
                "source_episode_count": record["source_episode_count"],
                "source_episode_ids": record["source_episode_ids"],
                "embedding": embedding,
                "embedding_model": self.config.model,
                "embedding_level": "podcast",
            }
            for record, embedding in zip(records, vectors)
        ]
