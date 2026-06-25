import type {
  EpisodeListResponse,
  EpisodeDetail,
  ChaptersResponse,
  TranscriptResponse,
  FactChecksResponse,
  SearchResponse,
} from "./types";

const BACKEND_URL = process.env.BACKEND_URL ?? "http://localhost:8080";

/** Public backend URL reachable from the browser (for audio streaming etc.) */
export function getPublicBackendUrl(): string {
  return process.env.NEXT_PUBLIC_BACKEND_URL ?? "http://localhost:8080";
}

async function backendFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BACKEND_URL}/api/v1${path}`, {
    ...init,
    cache: "no-store",
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Backend error ${res.status}: ${text}`);
  }
  return res.json() as Promise<T>;
}

export async function fetchEpisodes(params: {
  q?: string;
  cursor?: string;
  limit?: number;
}): Promise<EpisodeListResponse> {
  const sp = new URLSearchParams();
  if (params.q) sp.set("q", params.q);
  if (params.cursor) sp.set("cursor", params.cursor);
  if (params.limit) sp.set("limit", String(params.limit));
  const query = sp.toString() ? `?${sp}` : "";
  return backendFetch<EpisodeListResponse>(`/episodes${query}`);
}

export async function fetchEpisode(id: string): Promise<{ episode: EpisodeDetail }> {
  return backendFetch<{ episode: EpisodeDetail }>(`/episodes/${id}`);
}

export async function fetchChapters(id: string): Promise<ChaptersResponse | null> {
  const res = await fetch(`${BACKEND_URL}/api/v1/episodes/${id}/chapters`, {
    cache: "no-store",
  });
  if (res.status === 202) return null;
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Backend error ${res.status}: ${text}`);
  }
  return res.json() as Promise<ChaptersResponse>;
}

export async function fetchTranscript(id: string): Promise<TranscriptResponse> {
  return backendFetch<TranscriptResponse>(`/episodes/${id}/transcript`);
}

export async function fetchFactChecks(id: string): Promise<FactChecksResponse> {
  return backendFetch<FactChecksResponse>(`/episodes/${id}/fact-checks`);
}

export async function fetchSearch(params: {
  q: string;
  limit?: number;
  highlights?: number;
}): Promise<SearchResponse> {
  const sp = new URLSearchParams({ q: params.q });
  if (params.limit) sp.set("limit", String(params.limit));
  if (params.highlights) sp.set("highlights", String(params.highlights));

  try {
    return await backendFetch<SearchResponse>(`/search?${sp}`);
  } catch {
    // fallback to text search when embedding service is unavailable
    const { items } = await fetchEpisodes({ q: params.q, limit: params.limit });
    return {
      query: params.q,
      items: items.map((ep) => ({
        episode_id: ep.id,
        title: ep.title,
        podcast_name: ep.podcast_name,
        cover_url: ep.cover_url,
        score: 0,
        highlights: [],
      })),
      total: items.length,
    };
  }
}
