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
    incremental = "incremental"


class BatchStatus(str, Enum):
    pending = "pending"
    success = "success"
    failed = "failed"
    partial_success = "partial_success"


class PipelineBatch(BaseModel):
    id: uuid.UUID
    stage: PipelineStage
    load_mode: LoadMode
    status: BatchStatus
    start_ts: datetime
    fin_ts: datetime
    updated_at: datetime


class Podcast(BaseModel):
    id: uuid.UUID
    guid: str
    persons: Optional[str] = None
    feed_url: str
    title: str
    description: Optional[str] = None
    episode_count: Optional[int] = None
    categories: Optional[List[str]] = None
    image_url: Optional[str] = None
    ingested_at: Optional[datetime] = None
    published_at: Optional[datetime] = None
    batch_id: Optional[uuid.UUID] = None
    updated_at: Optional[datetime] = None
    system_updated_at: Optional[datetime] = None
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
    ingested_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    system_updated_at: Optional[datetime] = None
    enclosure_url: Optional[str] = None
    summary: Optional[str] = None
    batch_id: Optional[uuid.UUID] = None
