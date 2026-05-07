CREATE TYPE episode_status AS ENUM ('pending', 'processing', 'done', 'failed');
CREATE TYPE stage_status AS ENUM ('pending', 'running', 'done', 'failed');

-- sorted nach ingestion_start_ts descending -> grab last batch
-- store exception? -- maybe later
CREATE TABLE pipeline_runs (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ingestion_start_ts      TIMESTAMPTZ,
  ingestion_fin_ts        TIMESTAMPTZ,
  ingestion_status        stage_status NOT NULL DEFAULT 'pending',
  preprocessing_start_ts  TIMESTAMPTZ,
  preprocessing_fin_ts    TIMESTAMPTZ,
  preprocessing_status    stage_status NOT NULL DEFAULT 'pending',
  processing_start_ts     TIMESTAMPTZ,
  processing_fin_ts       TIMESTAMPTZ,
  processing_status       stage_status NOT NULL DEFAULT 'pending',
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE episodes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id         UUID REFERENCES pipeline_runs(id),
  title            TEXT NOT NULL,
  podcast_id       TEXT,
  podcast_name     TEXT,
  published_at     TIMESTAMPTZ,
  duration_seconds INTEGER,
  audio_path       TEXT,
  xml_path         TEXT,
  transcript_path  TEXT,
  cover_path       TEXT,
  status           episode_status NOT NULL DEFAULT 'pending',
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ingested_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE podcast_sections (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id      UUID NOT NULL REFERENCES episodes(id) ON DELETE CASCADE,
  section_idx     INT NOT NULL,
  text            TEXT,
  sentiment       TEXT,
  sentiment_score FLOAT,
  topics          TEXT[],
  processed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sections_episode_id ON podcast_sections(episode_id);
CREATE INDEX idx_episodes_batch_id ON episodes(batch_id);
CREATE INDEX idx_episodes_status ON episodes(status);


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




-- delta load full load

---
-- 12 Uhr Podcast release

-- 12:05 ingestion start -> start_ts der max_batch id
-- 12:10 Änderung der Quelle (Titel, etc) 
-- 12:30 processed -> end_ts der max batch id --> done for now
--> Event signals Change / loop fetch (fetch all entries where batch_start_ts < 13:00)
--> annahme update_ts für jedes field in quelle
--> prüfen welche fields sich geändert haben -> update_ts (quelle) > batch_start_ts (topf)
  --> returns count: über 5 lohnt sich drunter nicht oder so
--> update



-------
--> 


