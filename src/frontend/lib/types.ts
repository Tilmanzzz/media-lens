export type FactVerdict = "TRUE" | "MOSTLY_TRUE" | "MISLEADING" | "FALSE" | "UNVERIFIABLE";

export interface EpisodeCard {
  id: string;
  title: string;
  podcast_name: string;
  published_at: string;
  cover_url: string;
  summary: string;
  duration_seconds: number;
}

export interface EpisodeDetail extends EpisodeCard {}

export interface TranscriptLine {
  id: string;
  chapter_id: string;
  line_idx: number;
  start_time: number;
  end_time: number;
  text: string;
  emotion: string;
  emotion_score: number;
  has_fact_flag?: boolean;
}

export interface FactCheckedClaim {
  id: string;
  chapter_id: string;
  claim_idx: number;
  claim: string;
  verdict: FactVerdict;
  explanation: string;
  sources: string[];
}

export interface Chapter {
  id: string;
  episode_id?: string;
  chapter_idx: number;
  title: string;
  summary: string;
  start_time: number;
  end_time: number;
  transcript?: string | null;
  transcript_lines?: TranscriptLine[];
  fact_checked_claims?: FactCheckedClaim[];
}

export interface EpisodeListResponse {
  items: EpisodeCard[];
  next_cursor: string | null;
  total: number;
}

export interface ChaptersResponse {
  episode_id: string;
  chapters: Chapter[];
}

export interface TranscriptResponse {
  episode_id: string;
  lines: TranscriptLine[];
}

export interface FactChecksResponse {
  episode_id: string;
  claims: FactCheckedClaim[];
}
