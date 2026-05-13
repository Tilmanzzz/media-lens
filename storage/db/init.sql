CREATE EXTENSION IF NOT EXISTS vector;
-- Types

CREATE TYPE episode_status AS ENUM ('pending', 'processing', 'done', 'failed');
CREATE TYPE stage_status   AS ENUM ('pending', 'running',    'done', 'failed');

CREATE TYPE pipeline_step_type       AS ENUM ('ingestion', 'preprocessing', 'processing');

-- One row per podcast feed.
-- Manually inserted for now; the update script polls all rows here.
CREATE TABLE podcasts (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_url            TEXT        NOT NULL UNIQUE,
  title               TEXT,
  description         TEXT,
  image_url           TEXT,
  -- Polling state
  last_fetched_at     TIMESTAMPTZ,
  -- Content state
  last_content_at     TIMESTAMPTZ,
  -- Stored from HTTP response headers; used for conditional GET on next poll.
  -- Send If-None-Match / If-Modified-Since → skip processing on 304.
  feed_etag           TEXT,
  feed_last_modified  TEXT,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  max_episodes        INT DEFAULT NULL
);
-- One row per podcast episode.
-- guid (from RSS <guid>) + podcast_id is the natural deduplication key,
-- enabling safe upserts during feed polling.
CREATE TABLE episodes (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  podcast_id    UUID          NOT NULL REFERENCES podcasts(id)      ON DELETE CASCADE,
  guid          TEXT          NOT NULL,                             -- RSS <guid> --> primary key?
  title         TEXT          NOT NULL,
  published_at  TIMESTAMPTZ,
  duration_seconds INTEGER,

  -- MinIO object keys (bronze / silver)
  audio_key     TEXT          NOT NULL,                             -- bronze: raw audio
  xml_key       TEXT,                                               -- bronze: raw RSS XML
  transcript_key TEXT,                                              -- silver: Whisper JSON (set by processing)
  cover_key     TEXT,
  status        episode_status NOT NULL DEFAULT 'pending',
  ingested_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  enclosure_url TEXT,
  summary       TEXT,
  CONSTRAINT uq_episodes_podcast_guid UNIQUE (podcast_id, guid)
);


-- One row per transcript section produced by the processing module.
-- The processing module has full write ownership of this table and of
CREATE TABLE podcast_sections (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id      UUID        NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  section_idx     INT         NOT NULL,
  transcript      TEXT,
  sentiment       TEXT,
  sentiment_score REAL,
  topics          TEXT[],
  summary         TEXT,
  processed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);



CREATE TYPE emotion_label AS ENUM ('positive', 'neutral', 'negative');
CREATE TYPE fact_verdict AS ENUM ('TRUE', 'MOSTLY_TRUE', 'MISLEADING', 'FALSE', 'UNVERIFIABLE');

CREATE TABLE topics (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id  UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  topic       TEXT NOT NULL,
  start_time  INTEGER NOT NULL,
  emotion     emotion_label NOT NULL DEFAULT 'neutral',
  summary     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_topics_episode_id ON topics(episode_id);

CREATE TABLE transcript_lines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id  UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  start_time  INTEGER NOT NULL,
  text        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transcript_lines_episode_id ON transcript_lines(episode_id);

CREATE TABLE fact_checks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id  UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  start_time  INTEGER NOT NULL,
  claim       TEXT NOT NULL,
  verdict     fact_verdict NOT NULL DEFAULT 'UNVERIFIABLE',
  explanation TEXT,
  sources     TEXT[],
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fact_checks_episode_id ON fact_checks(episode_id);

CREATE TABLE conversations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id  UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conversations_episode_id ON conversations(episode_id);

CREATE TABLE embeddings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id      UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  chunk_id        TEXT,
  embedding_level TEXT NOT NULL,
  embedding       vector(384) NOT NULL,
  text            TEXT,
  start_time      INTEGER DEFAULT 0,
  episode_title   TEXT,
  podcast_name    TEXT,
  podcast_id      TEXT,
  cover_path      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (episode_id, chunk_id, embedding_level)
);

CREATE INDEX idx_embeddings_episode_id ON embeddings(episode_id);
CREATE INDEX idx_embeddings_level ON embeddings(embedding_level);
CREATE INDEX idx_embeddings_vector ON embeddings USING hnsw (embedding vector_cosine_ops);





-- Tables
-- One row per ingestion + processing run.
-- for now one script that combines ingestion and processing
-- one function call called by postgres scheduler that owns pipeline_runs table
CREATE TABLE pipeline_step(
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  start_ts              TIMESTAMPTZ,
  fin_ts                TIMESTAMPTZ,
  status                stage_status NOT NULL DEFAULT 'pending',
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  step_type             pipeline_step_type 
);





CREATE TABLE claims (
  id                  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id          UUID    NOT NULL REFERENCES podcast_sections(id) ON DELETE CASCADE,
  verdict             TEXT,
  verdict_explanation TEXT,
  sources             TEXT[],
  claim               TEXT
);



-- Indexes

CREATE INDEX idx_episodes_podcast_id  ON episodes(podcast_id);
CREATE INDEX idx_episodes_status      ON episodes(status);
CREATE INDEX idx_sections_episode_id  ON podcast_sections(episode_id);
CREATE INDEX idx_claims_section_id    ON claims(section_id);


-- automatic timestamp updates

CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER set_timestamp_podcasts
  BEFORE UPDATE ON podcasts
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();
 
CREATE TRIGGER set_timestamp_episodes
  BEFORE UPDATE ON episodes
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

