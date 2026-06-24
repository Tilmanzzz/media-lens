from __future__ import annotations

import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from dotenv import load_dotenv
from langchain_core.prompts import PromptTemplate
from langchain_ollama import ChatOllama

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src/02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

load_dotenv(Path(__file__).resolve().parents[3] / ".env")

from common.app_logger import AppLogger

from .text_summarizer_config import TextSummarizerConfig


class TextSummarizer:
    def __init__(
        self,
        config: Optional[TextSummarizerConfig] = None,
        config_path: Optional[str | Path] = None,
        logging_enabled: Optional[bool] = None,
        log_level: Optional[str] = None,
    ) -> None:
        if config is None:
            if config_path is not None:
                config = TextSummarizerConfig.from_file(config_path)
            else:
                config = TextSummarizerConfig.from_file("text_summarizer_config.json")
        self.config = config or TextSummarizerConfig()

        self._setup_logger(logging_enabled=logging_enabled, log_level=log_level)

        self.llm = self._build_llm()

        self.episode_prompt = PromptTemplate.from_template(
            """
You are summarizing a complete podcast episode.

{text}

Return ONLY the summary, no explanations, introduction or commentary.

Create:
1. An overall summary (2-3 sentences)
2. Key takeaways of the highlights (bullet list)

Output String:
    <summary here>
    
    Key Takeaways:
    - <takeaway 1>
    - <takeaway 2>
    - ...
""".strip()
        )

        self.chapter_prompt = PromptTemplate.from_template(
            """
Summarize the following podcast chapter in 1-3 sentences maximum.
Be concise and capture only the core message.

{text}

Return ONLY the summary, no explanations or commentary.
""".strip()
        )

        self.episode_chain = self.episode_prompt | self.llm
        self.chapter_chain = self.chapter_prompt | self.llm

        self.logger.debug("Initialized TextSummarizer with model=%s", self.config.model)

    def _build_llm(self):
        provider = (self.config.provider or "gemini").strip().lower()
        if provider == "ollama":
            return ChatOllama(
                model=self.config.model,
                temperature=self.config.temperature,
                **self.config.llm_options,
            )

        if provider == "gemini":
            try:
                from langchain_google_genai import \
                    ChatGoogleGenerativeAI  # type: ignore[import-not-found]
            except ImportError as exc:
                raise ImportError("Missing dependency: langchain-google-genai") from exc

            api_key = os.getenv("GEMINI_API_KEY")
            if not api_key:
                raise ValueError("GEMINI_API_KEY is not set in the environment")

            return ChatGoogleGenerativeAI(
                model=self.config.model,
                temperature=self.config.temperature,
                google_api_key=api_key,
                **self.config.llm_options,
            )

        raise ValueError(f"Unsupported LLM provider: {self.config.provider}")

    def _setup_logger(self, logging_enabled: Optional[bool], log_level: Optional[str]) -> None:
        enabled = self.config.logging_enabled if logging_enabled is None else logging_enabled
        level_name = (log_level or self.config.log_level or "INFO")

        log_dir = Path(self.config.log_dir)
        if not log_dir.is_absolute():
            log_dir = Path(__file__).resolve().parent / log_dir

        self.logger = AppLogger(
            module_name="text_summarizer",
            enabled=enabled,
            level=level_name,
            log_dir=log_dir,
            log_file=self.config.log_file,
        ).build()

    @staticmethod
    def group_by_episode(chunks: List[Dict[str, Any]]) -> Dict[Any, List[Dict[str, Any]]]:
        grouped: Dict[Any, List[Dict[str, Any]]] = defaultdict(list)
        for chunk in chunks:
            key = chunk["episode_id"]
            grouped[key].append(chunk)
        return grouped

    @staticmethod
    def group_by_chapter(chunks: List[Dict[str, Any]]) -> Dict[Tuple[Any, Any], List[Dict[str, Any]]]:
        grouped: Dict[Tuple[Any, Any], List[Dict[str, Any]]] = defaultdict(list)
        for chunk in chunks:
            key = (chunk["episode_id"], chunk["chapter_id"])
            grouped[key].append(chunk)
        return grouped

    @staticmethod
    def _sort_episode_chunks(episode_chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        return sorted(episode_chunks, key=lambda x: (x.get("chapter_id", 0), x.get("chunk_id", 0)))

    @staticmethod
    def _sort_chapter_chunks(chapter_chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        return sorted(chapter_chunks, key=lambda x: x.get("chunk_id", 0))

    @staticmethod
    def _extract_content(response: Any) -> str:
        raw = getattr(response, "content", None) or getattr(response, "text", None) or response
        if isinstance(raw, list):
            raw = " ".join(
                item.get("text", "")
                for item in raw
                if isinstance(item, dict) and item.get("type") == "text"
            )
        return re.sub(r"```(?:json)?\s*|\s*```", "", str(raw)).strip()

    def summarize_episode_chunks(self, episode_chunks: List[Dict[str, Any]]) -> str:
        ordered = self._sort_episode_chunks(episode_chunks)
        full_transcript = "\n\n".join(c.get("transcript_text", "") for c in ordered if c.get("transcript_text"))

        if not full_transcript.strip():
            return ""

        self.logger.debug("Summarizing episode with %d chunks", len(ordered))
        result = self.episode_chain.invoke({"text": full_transcript})
        return self._extract_content(result)

    def summarize_chapter_chunks(self, chapter_chunks: List[Dict[str, Any]]) -> str:
        ordered = self._sort_chapter_chunks(chapter_chunks)
        full_transcript = "\n\n".join(c.get("transcript_text", "") for c in ordered if c.get("transcript_text"))

        if not full_transcript.strip():
            return ""

        self.logger.debug("Summarizing chapter with %d chunks", len(ordered))
        result = self.chapter_chain.invoke({"text": full_transcript})
        return self._extract_content(result)

    def summarize_all_episodes(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        grouped = self.group_by_episode(chunks)
        results: List[Dict[str, Any]] = []

        for episode_id, episode_chunks in grouped.items():
            ordered = self._sort_episode_chunks(episode_chunks)
            summary = self.summarize_episode_chunks(ordered)

            if not ordered:
                continue

            self.logger.info("Episode summary created: episode=%s", episode_id)
            results.append(
                {
                    "episode_id": episode_id,
                    "episode_title": ordered[0].get("episode_title", ""),
                    "summary": summary,
                }
            )

        return results

    def summarize_all_chapters(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        grouped = self.group_by_chapter(chunks)
        results: List[Dict[str, Any]] = []

        for (episode_id, chapter_id), chapter_chunks in grouped.items():
            ordered = self._sort_chapter_chunks(chapter_chunks)
            summary = self.summarize_chapter_chunks(ordered)

            if not ordered:
                continue

            self.logger.info("Chapter summary created: episode=%s chapter=%s", episode_id, chapter_id)
            results.append(
                {
                    "episode_id": episode_id,
                    "episode_title": ordered[0].get("episode_title", ""),
                    "chapter_id": chapter_id,
                    "summary": summary,
                }
            )

        return results
