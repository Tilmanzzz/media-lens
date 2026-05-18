CREATE EXTENSION IF NOT EXISTS vector;

-- Technical batch control for stage-independent execution.
CREATE TYPE batch_status AS ENUM ('pending', 'running', 'done', 'failed', 'cancelled');
CREATE TYPE pipeline_stage AS ENUM ('ingestion', 'silver', 'silver_enriched');
CREATE TYPE load_mode AS ENUM ('full', 'incremental');
CREATE TYPE emotion_label AS ENUM ('positive', 'neutral', 'negative');
CREATE TYPE fact_verdict AS ENUM ('TRUE', 'MOSTLY_TRUE', 'MISLEADING', 'FALSE', 'UNVERIFIABLE');

-- One row per stage run. A stage can be started independently and can either
-- process the full source set or only the delta since the last watermark.
CREATE TABLE pipeline_batches (
  id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  stage                pipeline_stage NOT NULL,
  load_mode            load_mode     NOT NULL,
  status               batch_status  NOT NULL DEFAULT 'pending',
  start_ts             TIMESTAMPTZ   NOT NULL,
  fin_ts               TIMESTAMPTZ   NOT NULL,
  updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
  CONSTRAINT ck_pipeline_batches_time_range CHECK (fin_ts >= start_ts)
);

CREATE INDEX idx_pipeline_batches_stage_status ON pipeline_batches(stage, status);
CREATE INDEX idx_pipeline_batches_mode        ON pipeline_batches(load_mode);

-- Ingestion layer: feed metadata and episode discovery.
CREATE TABLE podcasts (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  guid                TEXT        NOT NULL,
  -- Text with people and their roles
  persons             TEXT,
  feed_url            TEXT        NOT NULL UNIQUE,
  title               TEXT        NOT NULL,
  description         TEXT,
  episode_count       INTEGER,
  image_url           TEXT,
  ingested_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  published_at        TIMESTAMPTZ,
  batch_id            UUID        REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  -- lastUpdateTime: The channel-level pubDate for the feed, if it’s sane.
  updated_at          TIMESTAMPTZ,
  system_updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  max_episodes        INT DEFAULT NULL,
  CONSTRAINT ck_podcasts_episode_count CHECK (episode_count IS NULL OR episode_count >= 0),
  CONSTRAINT ck_podcasts_max_episodes CHECK (max_episodes IS NULL OR max_episodes >= 0)
);

CREATE UNIQUE INDEX uq_podcasts_guid ON podcasts(guid);
CREATE INDEX idx_podcasts_updated_at ON podcasts(updated_at);


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
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  system_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  enclosure_url   TEXT,
  summary         TEXT,
  batch_id        UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  CONSTRAINT uq_episodes_podcast_guid UNIQUE (podcast_id, guid),
  CONSTRAINT ck_episodes_duration_seconds CHECK (duration_seconds IS NULL OR duration_seconds >= 0)
);

CREATE UNIQUE INDEX uq_episodes_guid ON episodes(guid);
CREATE INDEX idx_episodes_podcast_id ON episodes(podcast_id);
CREATE INDEX idx_episodes_updated_at ON episodes(updated_at);

-- Segments (chapters) per episode; a segment contains multiple transcript lines.
CREATE TABLE segments (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id      UUID          NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  segment_idx     INT           NOT NULL,
  title           TEXT,
  transcript      TEXT,
  summary         TEXT,
  start_time      INTEGER,
  end_time        INTEGER,
  batch_id        UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  system_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_segments_episode_idx UNIQUE (episode_id, segment_idx),
  CONSTRAINT ck_segments_segment_idx CHECK (segment_idx >= 0),
  CONSTRAINT ck_segments_time_range CHECK (end_time >= start_time),
  CONSTRAINT ck_segments_start_time CHECK (start_time >= 0),
  CONSTRAINT ck_segments_end_time CHECK (end_time >= 0)
);

CREATE INDEX idx_segments_episode_id ON segments(episode_id);
CREATE INDEX idx_segments_title ON segments(title);
CREATE INDEX idx_segments_system_updated_at ON segments(system_updated_at);


CREATE TABLE transcript_lines (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  segment_id      UUID          NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
  line_idx        INT           NOT NULL,
  start_time      INTEGER,
  end_time        INTEGER,
  text            TEXT NOT NULL,
  emotion         emotion_label DEFAULT 'neutral',
  emotion_score   REAL,
  batch_id        UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  system_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_transcript_lines_segment_idx UNIQUE (segment_id, line_idx),
  CONSTRAINT ck_transcript_lines_line_idx CHECK (line_idx >= 0),
  CONSTRAINT ck_transcript_lines_start_time CHECK (start_time >= 0),
  CONSTRAINT ck_transcript_lines_emotion_score CHECK (emotion_score IS NULL OR (emotion_score >= 0 AND emotion_score <= 1))
);

CREATE INDEX idx_transcript_lines_segment_id ON transcript_lines(segment_id);
CREATE INDEX idx_transcript_lines_system_updated_at ON transcript_lines(system_updated_at);

-- Claims per segment with verdicts and sources.
CREATE TABLE fact_checked_claims (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  segment_id        UUID          NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
  claim_idx         INT,
  claim             TEXT,
  verdict           fact_verdict DEFAULT 'UNVERIFIABLE',
  explanation       TEXT,
  sources           TEXT[],
  batch_id          UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  system_updated_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_fact_checked_claims_segment_idx UNIQUE (segment_id, claim_idx),
  CONSTRAINT ck_fact_checked_claims_claim_idx CHECK (claim_idx >= 0)
);

CREATE INDEX idx_fact_checked_claims_segment_id ON fact_checked_claims(segment_id);
CREATE INDEX idx_fact_checked_claims_system_updated_at ON fact_checked_claims(system_updated_at);

CREATE TABLE segment_embeddings (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  segment_id      UUID          NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
  embedding       vector(384),
  batch_id        UUID          REFERENCES pipeline_batches(id) ON DELETE SET NULL,
  system_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_segment_embeddings_segment UNIQUE (segment_id)
);

CREATE INDEX idx_segment_embeddings_segment_id ON segment_embeddings(segment_id);
CREATE INDEX idx_segment_embeddings_vector ON segment_embeddings USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_segment_embeddings_system_updated_at ON segment_embeddings(system_updated_at);

-- Fact-checked claims are stored in fact_checked_claims.

-- Timestamp maintenance for technical columns.
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trigger_set_system_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.system_updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_timestamp_pipeline_batches
  BEFORE UPDATE ON pipeline_batches
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TRIGGER set_timestamp_podcasts
  BEFORE UPDATE ON podcasts
  FOR EACH ROW EXECUTE FUNCTION trigger_set_system_timestamp();

CREATE TRIGGER set_timestamp_episodes
  BEFORE UPDATE ON episodes
  FOR EACH ROW EXECUTE FUNCTION trigger_set_system_timestamp();

CREATE TRIGGER set_timestamp_segments
  BEFORE UPDATE ON segments
  FOR EACH ROW EXECUTE FUNCTION trigger_set_system_timestamp();

CREATE TRIGGER set_timestamp_transcript_lines
  BEFORE UPDATE ON transcript_lines
  FOR EACH ROW EXECUTE FUNCTION trigger_set_system_timestamp();

CREATE TRIGGER set_timestamp_fact_checked_claims
  BEFORE UPDATE ON fact_checked_claims
  FOR EACH ROW EXECUTE FUNCTION trigger_set_system_timestamp();

CREATE TRIGGER set_timestamp_segment_embeddings
  BEFORE UPDATE ON segment_embeddings
  FOR EACH ROW EXECUTE FUNCTION trigger_set_system_timestamp();
