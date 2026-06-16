-- DROP SCHEMA public CASCADE;
-- CREATE SCHEMA public;

CREATE EXTENSION IF NOT EXISTS vector;

-- Technical batch control for stage-independent execution.
CREATE TYPE batch_status AS ENUM ('pending', 'success', 'failed', 'consumed', 'stopped');
CREATE TYPE pipeline_stage AS ENUM ('ingestion', 'transcription', 'segmenting', 'text_summarizer', 'embedder', 'emotion_scoring', 'fact_checker');
CREATE TYPE load_mode AS ENUM ('full', 'delta');
CREATE TYPE emotion_label AS ENUM ('happy', 'neutral', 'angry', 'sad');
CREATE TYPE fact_verdict AS ENUM ('TRUE', 'MOSTLY_TRUE', 'MISLEADING', 'FALSE', 'UNVERIFIABLE');

-- One row per stage run. A stage can be started independently and can either
-- process the full source set or only the delta since the last watermark.
CREATE TABLE pipeline_batches (
  id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  stage                pipeline_stage NOT NULL,
  load_mode            load_mode     NOT NULL,
  status               batch_status  NOT NULL DEFAULT 'pending',
  start_ts             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  fin_ts               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT ck_pipeline_batches_time_range CHECK (fin_ts >= start_ts)
);

CREATE INDEX idx_pipeline_batches_stage_status ON pipeline_batches(stage, status);
CREATE INDEX idx_pipeline_batches_mode        ON pipeline_batches(load_mode);

-- Ingestion layer: feed metadata and episode discovery.
CREATE TABLE podcasts (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  guid                TEXT        NOT NULL,
  -- Text with people and their roles
  hosts               TEXT,
  feed_url            TEXT        NOT NULL UNIQUE,
  title               TEXT        NOT NULL,
  description         TEXT,
  episode_count       INTEGER,
  categories          TEXT[],
  image_url           TEXT,
  ingested_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  published_at        TIMESTAMPTZ,
  batch_id            UUID        REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  -- lastUpdateTime: The channel-level pubDate for the feed, if it’s sane.
  source_system_updated_at          TIMESTAMPTZ,
  preprocessing_updated_at TIMESTAMPTZ,
  ingestion_updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  max_episodes        INT DEFAULT NULL,
  CONSTRAINT ck_podcasts_episode_count CHECK (episode_count IS NULL OR episode_count >= 0),
  CONSTRAINT ck_podcasts_max_episodes CHECK (max_episodes IS NULL OR max_episodes >= 0)
);

CREATE UNIQUE INDEX uq_podcasts_guid ON podcasts(guid);
CREATE INDEX idx_podcasts_processing_updated_at ON podcasts(processing_updated_at);
CREATE INDEX idx_podcasts_preprocessing_updated_at ON podcasts(preprocessing_updated_at); 
CREATE INDEX idx_podcasts_ingestion_updated_at ON podcasts(ingestion_updated_at);
CREATE INDEX idx_podcasts_source_system_updated_at ON podcasts(source_system_updated_at);


-- One row per podcast episode.
CREATE TABLE episodes (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  podcast_id      UUID          NOT NULL REFERENCES podcasts(id) ON DELETE CASCADE,
  -- It assigns a globally unique ID to every podcast.
  guid            TEXT          NOT NULL,
  title           TEXT          NOT NULL,
  published_at    TIMESTAMPTZ,
  duration_seconds INTEGER,
  audio_key       TEXT          NOT NULL,
  xml_key         TEXT,
  transcript_key  TEXT,
  cover_key       TEXT,
  ingested_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  source_system_updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  processing_updated_at TIMESTAMPTZ,
  preprocessing_updated_at TIMESTAMPTZ,
  ingestion_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  enclosure_url   TEXT,
  summary         TEXT,
  batch_id        UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  CONSTRAINT uq_episodes_podcast_guid UNIQUE (podcast_id, guid),
  CONSTRAINT ck_episodes_duration_seconds CHECK (duration_seconds IS NULL OR duration_seconds >= 0)
);

CREATE UNIQUE INDEX uq_episodes_guid ON episodes(guid);
CREATE INDEX idx_episodes_podcast_id ON episodes(podcast_id);
CREATE INDEX idx_episodes_processing_updated_at ON episodes(processing_updated_at);
CREATE INDEX idx_episodes_preprocessing_updated_at ON episodes(preprocessing_updated_at);
CREATE INDEX idx_episodes_ingestion_updated_at ON episodes(ingestion_updated_at);
CREATE INDEX idx_episodes_source_system_updated_at ON episodes(source_system_updated_at);


-- Segments (chapters) per episode; a chapter contains multiple transcript lines.
CREATE TABLE chapters (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id      UUID          NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  chapter_idx     INT           NOT NULL,
  title           TEXT,
  transcript      TEXT,
  summary         TEXT,
  start_time      REAL NOT NULL,
  end_time        REAL NOT NULL,
  batch_id        UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  preprocessing_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processing_updated_at TIMESTAMPTZ,
  CONSTRAINT uq_chapters_episode_idx UNIQUE (episode_id, chapter_idx),
  CONSTRAINT ck_chapters_chapter_idx CHECK (chapter_idx >= 0),
  CONSTRAINT ck_chapters_time_range CHECK (end_time >= start_time),
  CONSTRAINT ck_chapters_start_time CHECK (start_time >= 0),
  CONSTRAINT ck_chapters_end_time CHECK (end_time >= 0)
);

CREATE INDEX idx_chapters_episode_id ON chapters(episode_id);
CREATE INDEX idx_chapters_title ON chapters(title);
CREATE INDEX idx_chapters_preprocessing_updated_at ON chapters(preprocessing_updated_at);
CREATE INDEX idx_chapters_processing_updated_at ON chapters(processing_updated_at);

-- punkt chapteriert
CREATE TABLE transcript_lines (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_id      UUID          NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
  line_idx        INT           NOT NULL,
  start_time      REAL NOT NULL,
  end_time        REAL NOT NULL,
  text            TEXT NOT NULL,
  emotion         emotion_label DEFAULT 'neutral',
  emotion_score   REAL DEFAULT 0,
  batch_id        UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  processing_updated_at TIMESTAMPTZ,
  preprocessing_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_transcript_lines_chapter_idx UNIQUE (chapter_id, line_idx),
  CONSTRAINT ck_transcript_lines_line_idx CHECK (line_idx >= 0),
  CONSTRAINT ck_transcript_lines_start_time CHECK (start_time >= 0),
  CONSTRAINT ck_transcript_lines_emotion_score CHECK (emotion_score IS NULL OR (emotion_score >= 0 AND emotion_score <= 1))
);

CREATE INDEX idx_transcript_lines_chapter_id ON transcript_lines(chapter_id);
CREATE INDEX idx_transcript_lines_preprocessing_updated_at ON transcript_lines(preprocessing_updated_at);
CREATE INDEX idx_transcript_lines_processing_updated_at ON transcript_lines(processing_updated_at);

-- Claims per chapter with verdicts and sources.
CREATE TABLE fact_checked_claims (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_id        UUID          NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
  claim_idx         INT,
  claim             TEXT,
  verdict           fact_verdict DEFAULT 'UNVERIFIABLE',
  explanation       TEXT,
  sources           TEXT[],
  batch_id          UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  processing_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_fact_checked_claims_chapter_idx UNIQUE (chapter_id, claim_idx),
  CONSTRAINT ck_fact_checked_claims_claim_idx CHECK (claim_idx >= 0)
);

CREATE INDEX idx_fact_checked_claims_chapter_id ON fact_checked_claims(chapter_id);
CREATE INDEX idx_fact_checked_claims_processing_updated_at ON fact_checked_claims(processing_updated_at);

CREATE TYPE embedding_level AS ENUM ('chapter', 'episode', 'podcast');
CREATE TABLE embeddings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_id UUID REFERENCES chapters(id) ON DELETE CASCADE,
  episode_id UUID REFERENCES episodes(id) ON DELETE CASCADE,
  podcast_id UUID REFERENCES podcasts(id) ON DELETE CASCADE,
  level embedding_level NOT NULL,
  embedding halfvec(2560),
  batch_id UUID REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  processing_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT embeddings_level_fk_check CHECK (
    (
      level = 'podcast'
      AND podcast_id IS NOT NULL
      AND episode_id IS NULL
      AND chapter_id IS NULL
    )
    OR
    (
      level = 'episode'
      AND episode_id IS NOT NULL
      AND podcast_id IS NULL
      AND chapter_id IS NULL
    )
    OR
    (
      level = 'chapter'
      AND chapter_id IS NOT NULL
      AND podcast_id IS NULL
      AND episode_id IS NULL
    )
  )
);

CREATE INDEX idx_embeddings_vector
ON embeddings
USING hnsw (embedding halfvec_cosine_ops);

CREATE INDEX idx_embeddings_processing_updated_at
ON embeddings(processing_updated_at);

CREATE UNIQUE INDEX uq_embeddings_podcast
ON embeddings(podcast_id)
WHERE level = 'podcast';

CREATE UNIQUE INDEX uq_embeddings_episode
ON embeddings(episode_id)
WHERE level = 'episode';

CREATE UNIQUE INDEX uq_embeddings_chapter
ON embeddings(chapter_id)
WHERE level = 'chapter';

-- Fact-checked claims are stored in fact_checked_claims.
