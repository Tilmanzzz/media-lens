CREATE TABLE episodes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title         TEXT NOT NULL,
  podcast_id    TEXT,
  published_at  TIMESTAMPTZ,
  audio_path    TEXT,   -- e.g. 'bronze/podcasts/ep123.mp3'
  xml_path      TEXT,   -- e.g. 'bronze/podcasts/ep123.xml'
  ingested_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE podcast_sections (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id      UUID REFERENCES episodes(id) ON DELETE CASCADE,
  section_idx     INT NOT NULL,
  text            TEXT,
  sentiment       TEXT,
  sentiment_score FLOAT,
  topics          TEXT[],
  processed_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_sections_episode_id ON podcast_sections(episode_id);
