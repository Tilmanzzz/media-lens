from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from ddgs import DDGS
from ddgs.exceptions import DDGSException
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_ollama import ChatOllama

SRC_DIR = str(Path(__file__).resolve()).split("src")[0] + "src/02_processing"
if str(SRC_DIR) not in sys.path:
    sys.path.append(str(SRC_DIR))

load_dotenv(Path(__file__).resolve().parents[3] / ".env")

from common.app_logger import AppLogger

from .fact_checker_config import FactCheckerConfig


def _strip_code_fences(text: str) -> str:
    return text.replace("```json", "").replace("```", "").strip()


def _parse_json(text: str, fallback: Any) -> Any:
    try:
        return json.loads(_strip_code_fences(text))
    except Exception:
        return fallback


def _response_to_text(response: Any) -> str:
    raw = getattr(response, "content", None) or getattr(response, "text", None) or ""
    if isinstance(raw, list):
        raw = " ".join(
            item.get("text", "")
            for item in raw
            if isinstance(item, dict) and item.get("type") == "text"
        )
    return re.sub(r"```(?:json)?\s*|\s*```", "", str(raw)).strip()


def _dedupe_preserve_order(items: Iterable[str]) -> List[str]:
    seen = set()
    ordered: List[str] = []
    for item in items:
        value = item.strip()
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


_TRANSPORT_ERROR_HINTS = (
    "error sending request",
    "connection refused",
    "connection reset",
    "connection aborted",
    "failed to lookup address",
    "name resolution",
    "name or service not known",
    "tls",
    "ssl",
    "timed out",
    "timeout",
)


def _is_transport_error(exc: Exception) -> bool:
    """Detect low-level connection/transport failures (DNS, TLS, refused, timeout, ...).

    These will not resolve by retrying the exact same request, unlike a transient
    "no results" response from a single search backend.
    """
    message = str(exc).lower()
    return any(hint in message for hint in _TRANSPORT_ERROR_HINTS)


def _compact_sources(raw_results: Iterable[Dict[str, Any]], limit: int) -> List[Dict[str, str]]:
    compacted: List[Dict[str, str]] = []
    seen_urls = set()

    for result in raw_results:
        url = str(result.get("href") or result.get("url") or "").strip()
        if not url or url in seen_urls:
            continue

        seen_urls.add(url)
        compacted.append(
            {
                "url": url,
                "title": str(result.get("title") or "").strip(),
                "snippet": str(result.get("body") or result.get("snippet") or "").strip(),
            }
        )

        if len(compacted) >= limit:
            break

    return compacted


class FactChecker:
    def __init__(
        self,
        config: Optional[FactCheckerConfig] = None,
        config_path: Optional[str | Path] = None,
        logging_enabled: Optional[bool] = None,
        log_level: Optional[str] = None,
    ):
        if config is None and config_path is not None:
            config = FactCheckerConfig.from_file(config_path)
        self.config = config or FactCheckerConfig()
        self._setup_logger(logging_enabled=logging_enabled, log_level=log_level)
        self.llm = self._build_llm()
        self.logger.debug(
            "Initialized FactChecker with provider=%s model=%s region=%s",
            self.config.provider,
            self.config.model,
            self.config.region,
        )

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
            module_name="fact_checker",
            enabled=enabled,
            level=level_name,
            log_dir=log_dir,
            log_file=self.config.log_file,
        ).build()

    def set_logging(self, enabled: bool, log_level: Optional[str] = None) -> None:
        self._setup_logger(logging_enabled=enabled, log_level=log_level)

    def fact_check(self, transcript: str) -> Dict[str, List[Dict[str, Any]]]:
        self.logger.info("Starting fact check")
        claims = self._extract_claims(transcript)
        self.logger.info("Extracted %d claims", len(claims))
        if not claims:
            self.logger.info("No factual claims found")
            return {"claims": []}

        research = self._research_claims(claims)
        self.logger.info("Research completed with %d results", sum(len(v) for v in research.values()))
        verdicts = self._verify_claims(research)
        self.logger.info("Fact check completed with %d verdicts", len(verdicts))
        return {"claims": verdicts}

    def fact_check_json(self, transcript: str, indent: Optional[int] = None) -> str:
        return json.dumps(self.fact_check(transcript), indent=indent, ensure_ascii=False)

    def _extract_claims(self, transcript: str) -> List[str]:
        system_prompt = """
        You are an expert in extracting factual claims from transcript text.

        Rules:
        1. Extract only verifiable, real-world factual claims.
        2. Ignore pure opinions, jokes, speculation, rhetorical questions and personal preferences.
        IMPORTANT: A claim does NOT become an opinion just because it is stated in a conversation.
        "Studies show X" or "X is the scientific consensus" are factual claims, not opinions.
        3. Return ONLY a JSON list of claim strings. No markdown.
        4. If no factual claims exist, return [].
        """.strip()

        prompt = f"""
        Extract factual claims from this transcript.
        Examples of claims to extract:
        - References to specific studies, journals, or publications
        - Statements about scientific consensus or research findings  
        - Quantitative comparisons or performance statements
        - Named sources with dates

        Transcript:
        {transcript}
        
        Return ONLY a raw JSON array of strings.
        No markdown, no code fences, no explanation.
        Example output: ["Claim one.", "Claim two."]
        """.strip()
        
        response = self.llm.invoke([
            SystemMessage(content=system_prompt),
            HumanMessage(content=prompt),
        ])

        # Ollama/gemma returns a string, Gemini returns a list of dicts.
        claims = _parse_json(_response_to_text(response), [])
        if not isinstance(claims, list):
            self.logger.warning("Claim extraction response was not a JSON list")
            return []

        cleaned = [str(c).strip() for c in claims if str(c).strip()]
        return _dedupe_preserve_order(cleaned)

    def _generate_queries(self, claim: str) -> List[str]:
        system_prompt = """
        You are an expert researcher.
        Generate concise search queries that are likely to find high-quality evidence for a claim.
        Return ONLY a JSON list of strings.
        """.strip()

        prompt = f"""
        Generate {self.config.max_queries_per_claim} search queries for this claim.

        Claim:
        {claim}
        
        Return ONLY a JSON list of strings.
        Example output: ["Query one", "Query two"]
        """.strip()

        response = self.llm.invoke(
            [
                SystemMessage(content=system_prompt),
                HumanMessage(content=prompt),
            ]
        )

        queries = _parse_json(_response_to_text(response), [])
        if not isinstance(queries, list):
            return [claim]

        cleaned = [str(q).strip() for q in queries if str(q).strip()]
        deduped = _dedupe_preserve_order(cleaned)
        self.logger.debug("Generated %d queries for claim: %s", len(deduped), claim)
        return deduped[: self.config.max_queries_per_claim] or [claim]

    def _research_claims(self, claims: List[str]) -> Dict[str, List[Dict[str, str]]]:
        research_data: Dict[str, List[Dict[str, str]]] = {}

        with DDGS(timeout=self.config.search_timeout) as ddgs:
            for claim in claims:
                self.logger.debug("Researching claim: %s", claim)
                queries = self._generate_queries(claim)
                raw_results: List[Dict[str, Any]] = []

                for query in queries:
                    max_attempts = 3
                    for attempt in range(1, max_attempts + 1):
                        try:
                            result_iter = ddgs.text(
                                query,
                                max_results=self.config.max_search_results_per_query,
                                region=self.config.region,
                                backend=self.config.search_backend,
                            )
                            raw_results.extend(list(result_iter))
                            break
                        except DDGSException as exc:
                            message = str(exc)
                            if "No results found" in message:
                                self.logger.warning("Search returned no results: %s", query)
                                break

                            if _is_transport_error(exc):
                                self.logger.error(
                                    "Search failed due to connection/transport error, no retry: %s | %s",
                                    query,
                                    message,
                                )
                                break

                            if attempt >= max_attempts:
                                self.logger.exception("Search failed after retries: %s", query)
                                break

                            backoff = 0.5 * (2 ** (attempt - 1))
                            self.logger.warning(
                                "Search failed (attempt %d/%d), retry in %.1fs: %s",
                                attempt,
                                max_attempts,
                                backoff,
                                query,
                            )
                            time.sleep(backoff)
                        except Exception as exc:
                            if _is_transport_error(exc):
                                self.logger.error(
                                    "Search failed due to connection/transport error, no retry: %s | %s",
                                    query,
                                    str(exc),
                                )
                                break

                            if attempt >= max_attempts:
                                self.logger.exception("Search failed after retries: %s", query)
                                break
                            backoff = 0.5 * (2 ** (attempt - 1))
                            self.logger.warning(
                                "Search failed (attempt %d/%d), retry in %.1fs: %s",
                                attempt,
                                max_attempts,
                                backoff,
                                query,
                            )
                            time.sleep(backoff)

                research_data[claim] = _compact_sources(raw_results, self.config.max_sources_per_claim)
                self.logger.debug(
                    "Collected %d compacted sources for claim",
                    len(research_data[claim]),
                )

        return research_data

    def _verify_claims(self, research: Dict[str, List[Dict[str, str]]]) -> List[Dict[str, Any]]:
        verdicts: List[Dict[str, Any]] = []
        allowed_verdicts = ", ".join(self.config.allowed_verdicts)

        for claim in research.keys():
            sources = research[claim]
            if not sources:
                self.logger.debug("No sources found for claim, marking UNVERIFIABLE: %s", claim)
                verdicts.append(
                    {
                        "claim": claim,
                        "verdict": "UNVERIFIABLE",
                        "explanation": "No reliable evidence could be retrieved for this claim.",
                        "sources": [],
                    }
                )
                continue

            system_prompt = f"""
            You are a professional fact checker.
            Use ONLY the provided evidence. Do not use outside knowledge.
            The explanation MUST BE concise and easy to understand.

            Allowed verdicts: {allowed_verdicts}

            Return ONLY valid JSON with this schema:
            {{
            "claim": "...",
            "verdict": "...",
            "explanation": "...",
            "sources": ["https://..."]
            }}
            """.strip()

            verify_prompt = f"""
            Claim:
            {claim}

            Available Evidence:
            {research[claim]}
            """.strip()

            response = self.llm.invoke(
                [
                    SystemMessage(content=system_prompt),
                    HumanMessage(content=verify_prompt),
                ]
            )

            parsed = _parse_json(_response_to_text(response), {})
            if not isinstance(parsed, dict):
                self.logger.warning("Verifier response was not a JSON object for claim: %s", claim)
            verdicts.append(self._normalize_verdict(claim, parsed, sources))

        return verdicts

    def _normalize_verdict(
        self,
        claim: str,
        parsed: Dict[str, Any],
        fallback_sources: List[Dict[str, str]],
    ) -> Dict[str, Any]:
        if not isinstance(parsed, dict):
            parsed = {}

        verdict = str(parsed.get("verdict", "UNVERIFIABLE")).strip().upper()
        if verdict not in self.config.allowed_verdicts:
            verdict = "UNVERIFIABLE"

        explanation = str(parsed.get("explanation", "Parsing failed or insufficient evidence.")).strip()

        source_urls = parsed.get("sources", [])
        if not isinstance(source_urls, list):
            source_urls = []

        normalized_sources = [str(url).strip() for url in source_urls if str(url).strip()]
        if not normalized_sources:
            normalized_sources = [src["url"] for src in fallback_sources if src.get("url")]

        normalized_sources = _dedupe_preserve_order(normalized_sources)[: self.config.max_sources_per_claim]

        return {
            "claim": claim,
            "verdict": verdict,
            "explanation": explanation,
            "sources": normalized_sources,
        }
