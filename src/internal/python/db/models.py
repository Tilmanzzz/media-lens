from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import uuid
from enum import Enum


class PipelineStage(str, Enum):
    ingestion = "ingestion"
    transcription = "transcription"
    segmenting = "segmenting"
    processing = "processing"


class LoadMode(str, Enum):
    full = "full"
    delta = "delta"


class BatchStatus(str, Enum):
    pending = "pending"
    success = "success"
    failed = "failed"
    consumed = "consumed"
    stopped = "stopped"


class EmotionLabel(str, Enum):
    happy = "happy"
    neutral = "neutral"
    angry = "angry"
    sad = "sad"


class FactVerdict(str, Enum):
    TRUE = "TRUE"
    MOSTLY_TRUE = "MOSTLY_TRUE"
    MISLEADING = "MISLEADING"
    FALSE = "FALSE"
    UNVERIFIABLE = "UNVERIFIABLE"


class EmbeddingLevel(str, Enum):
    chapter = "chapter"
    episode = "episode"
    podcast = "podcast"


class PipelineBatch(BaseModel):
    id: uuid.UUID
    stage: PipelineStage
    load_mode: LoadMode
    status: BatchStatus
    start_ts: datetime
    fin_ts: datetime


class Podcast(BaseModel):
    id: uuid.UUID
    guid: str
    hosts: Optional[str] = None
    feed_url: str
    title: str
    description: Optional[str] = None
    episode_count: Optional[int] = None
    categories: Optional[List[str]] = None
    image_url: Optional[str] = None
    ingested_at: datetime
    published_at: Optional[datetime] = None
    batch_id: Optional[uuid.UUID] = None
    source_system_updated_at: Optional[datetime] = None
    processing_updated_at: Optional[datetime] = None
    preprocessing_updated_at: Optional[datetime] = None
    ingestion_updated_at: datetime
    max_episodes: Optional[int] = None


class Episode(BaseModel):
    id: uuid.UUID
    podcast_id: uuid.UUID
    guid: str
    title: str
    published_at: Optional[datetime] = None
    duration_seconds: Optional[int] = None
    audio_key: str
    xml_key: Optional[str] = None
    transcript_key: Optional[str] = None
    cover_key: Optional[str] = None
    ingested_at: datetime
    source_system_updated_at: datetime
    processing_updated_at: Optional[datetime] = None
    preprocessing_updated_at: Optional[datetime] = None
    ingestion_updated_at: datetime
    enclosure_url: Optional[str] = None
    summary: Optional[str] = None
    batch_id: Optional[uuid.UUID] = None


class Chapter(BaseModel):
    id: uuid.UUID
    episode_id: uuid.UUID
    chapter_idx: int
    title: Optional[str] = None
    transcript: Optional[str] = None
    summary: Optional[str] = None
    start_time: float
    end_time: float
    batch_id: Optional[uuid.UUID] = None
    preprocessing_updated_at: datetime
    processing_updated_at: Optional[datetime] = None


class TranscriptLine(BaseModel):
    id: uuid.UUID
    chapter_id: uuid.UUID
    line_idx: int
    start_time: float
    end_time: float
    text: str
    emotion: Optional[EmotionLabel] = EmotionLabel.neutral
    emotion_score: Optional[float] = None
    batch_id: Optional[uuid.UUID] = None
    processing_updated_at: Optional[datetime] = None
    preprocessing_updated_at: datetime


class FactCheckedClaim(BaseModel):
    id: uuid.UUID
    chapter_id: uuid.UUID
    claim_idx: Optional[int] = None
    claim: Optional[str] = None
    verdict: Optional[FactVerdict] = FactVerdict.UNVERIFIABLE
    explanation: Optional[str] = None
    sources: Optional[List[str]] = None
    batch_id: Optional[uuid.UUID] = None
    processing_updated_at: datetime


class Embedding(BaseModel):
    id: uuid.UUID
    chapter_id: Optional[uuid.UUID] = None
    episode_id: Optional[uuid.UUID] = None
    podcast_id: Optional[uuid.UUID] = None
    level: EmbeddingLevel
    embedding: Optional[List[float]] = None
    batch_id: Optional[uuid.UUID] = None
    processing_updated_at: datetime
