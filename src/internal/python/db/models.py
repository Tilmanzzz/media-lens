from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import uuid


class Podcast(BaseModel):
    id: uuid.UUID
    feed_url: str
    feed_etag: Optional[str] = None
    feed_last_modified: Optional[str] = None
    max_episodes: Optional[int] = None


class Episode(BaseModel):
    id: uuid.UUID
    podcast_id: str
    guid: str
    title: str
    audio_key: str
    status: str
    published_at: Optional[datetime] = None
    enclosure_url: Optional[str] = None


class Word(BaseModel):
    word: str
    start: float
    end: float
    probability: float


class TranscriptSegment(BaseModel):
    start: float
    end: float
    text: str
    words: Optional[List[Word]] = None
