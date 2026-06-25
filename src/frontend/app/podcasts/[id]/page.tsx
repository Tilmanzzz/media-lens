import { notFound } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import type { Chapter, FactVerdict } from "@/lib/types";
import PodcastDetailClient from "@/components/ui/podcastClient";
import { InfoCard } from "@/components/ui/card";
import { fetchEpisode, fetchChapters, fetchTranscript, fetchFactChecks, fetchEpisodes } from "@/lib/api";

const knownVerdicts = new Set<string>(["TRUE", "MOSTLY_TRUE", "MISLEADING", "FALSE", "UNVERIFIABLE"]);
const safeVerdict = (v: string): FactVerdict =>
  knownVerdicts.has(v) ? (v as FactVerdict) : "UNVERIFIABLE";

function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

export default async function PodcastDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  let episode: Awaited<ReturnType<typeof fetchEpisode>>["episode"];
  try {
    const result = await fetchEpisode(id);
    episode = result.episode;
  } catch {
    notFound();
  }

  const [chaptersResult, transcriptResult, factChecksResult, recommendedResult] = await Promise.all([
    fetchChapters(id).catch(() => null),
    fetchTranscript(id).catch(() => ({ episode_id: id, lines: [] })),
    fetchFactChecks(id).catch(() => ({ episode_id: id, claims: [] })),
    fetchEpisodes({ limit: 4 }),
  ]);

  const rawChapters = chaptersResult?.chapters ?? [];

  const linesByChapter = new Map<string, typeof transcriptResult.lines>();
  for (const line of transcriptResult.lines) {
    const bucket = linesByChapter.get(line.chapter_id) ?? [];
    bucket.push(line);
    linesByChapter.set(line.chapter_id, bucket);
  }

  const claimsByChapter = new Map<string, typeof factChecksResult.claims>();
  for (const claim of factChecksResult.claims) {
    const bucket = claimsByChapter.get(claim.chapter_id) ?? [];
    bucket.push({ ...claim, verdict: safeVerdict(claim.verdict) });
    claimsByChapter.set(claim.chapter_id, bucket);
  }

  const chapters: Chapter[] = rawChapters.map((ch) => ({
    ...ch,
    transcript_lines: linesByChapter.get(ch.id) ?? [],
    fact_checked_claims: claimsByChapter.get(ch.id) ?? [],
  }));

  const emotionData = {
    segments: transcriptResult.lines.map((line) => ({
      start: line.start_time,
      end: line.end_time,
      dominant: line.emotion,
      score: line.emotion_score,
    })),
  };

  const recommended = recommendedResult.items
    .filter((ep) => ep.id !== id)
    .slice(0, 3);

  return (
    <div className="min-h-screen flex flex-col px-4 py-12">
      <div className="flex items-center justify-center rounded-2xl w-40 h-10 mb-4 bg-primary">
        <Link href="/">Back to Home</Link>
      </div>

      <div className="flex rounded-xl">
        <div className="w-full max-w-lg self-center rounded-2xl mb-8">
          {episode.cover_url ? (
            <Image
              src={episode.cover_url}
              alt={episode.title}
              width={400}
              height={400}
              className="object-cover"
            />
          ) : (
            <div className="w-[400px] h-[400px] rounded-2xl bg-background-card flex items-center justify-center">
              <span className="text-foreground-subtle text-sm">Kein Cover</span>
            </div>
          )}
        </div>
        <div className="w-full max-w-1xl flex flex-col mb-8 gap-4">
          <p className="text-sm text-gray-500 uppercase tracking-widest">
            {episode.podcast_name}
          </p>
          <h1 className="text-3xl font-bold">{episode.title}</h1>
          {episode.summary && (
            <p className="text-base leading-relaxed mt-2">{episode.summary}</p>
          )}
          <div className="flex gap-20 text-sm">
            <span>{formatDuration(episode.duration_seconds)}</span>
            <span>{new Date(episode.published_at).toLocaleDateString("de-DE", { year: "numeric", month: "long", day: "numeric" })}</span>
          </div>
        </div>
      </div>

      <PodcastDetailClient
        src={episode.audio_url ?? "/sample-3s.mp3"}
        episodeId={episode.id}
        chapters={chapters}
        emotionData={emotionData}
      />

      {recommended.length > 0 && (
        <div className="mt-10">
          <h2 className="text-lg font-semibold text-foreground mb-4">Das könnte dir auch gefallen</h2>
          <div className="grid gap-6 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
            {recommended.map((item) => (
              <InfoCard key={item.id} {...item} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
