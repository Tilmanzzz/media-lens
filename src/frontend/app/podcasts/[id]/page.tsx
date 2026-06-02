import { foundPodcast } from "@/lib/dummyData";
import { notFound } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import type { Chapter } from "@/lib/types";
import PodcastDetailClient from "@/components/ui/podcastClient";
import { InfoCard } from "@/components/ui/card";

export default async function PodcastDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const episode = foundPodcast.find((p) => p.id === id);
  if (!episode) notFound();

  const badges = episode.badge.split(",").map((b) => b.trim());

  const emotionData = {
    segments: [
      { start: 0,   end: 175, dominant: "Anger", score: 0.85 },
      { start: 175, end: 295, dominant: "Calm",  score: 0.62 },
      { start: 295, end: 497, dominant: "Fear",  score: 0.38 },
    ],
  };

  const chapters: Chapter[] = [
    {
      id: "40000000-0000-0000-0000-000000000007",
      episode_id: id,
      chapter_idx: 0,
      title: 'The "97% consensus" claim: true, misleading, or both?',
      transcript: null,
      summary: "A 2013 study found 97.1% of climate scientists agree on human-caused warming, based on a review of over 12,000 peer-reviewed abstracts.",
      start_time: 0.0,
      end_time: 720.0,
      transcript_lines: [
        {
          id: "tl-1",
          chapter_id: "40000000-0000-0000-0000-000000000007",
          line_idx: 0,
          start_time: 0,
          end_time: 12,
          text: "Sarah: Let's start with the most cited number in climate discourse: 97% of scientists agree on climate change.",
          emotion: "neutral",
          emotion_score: 0.8,
        },
        {
          id: "tl-2",
          chapter_id: "40000000-0000-0000-0000-000000000007",
          line_idx: 1,
          start_time: 12,
          end_time: 28,
          text: "James: It's real, but it needs context. The figure comes from a 2013 meta-analysis by Cook et al.",
          emotion: "neutral",
          emotion_score: 0.7,
        },
      ],
      fact_checked_claims: [
        {
          id: "fc-1",
          chapter_id: "40000000-0000-0000-0000-000000000007",
          claim_idx: 0,
          claim: "97% of scientists agree on climate change.",
          verdict: "MOSTLY_TRUE",
          explanation: "Die 97% stammen aus einer Metaanalyse von Cook et al. (2013), die über 12.000 Abstracts auswertete.",
          sources: ["https://iopscience.iop.org/article/10.1088/1748-9326/8/2/024024"],
        },
      ],
    },
  ];


  const recommended = foundPodcast
    .filter((p) => p.id !== id)
    .slice(0, 3);

  return (
    <div className="min-h-screen flex flex-col px-4 py-12">
      <div className="flex items-center justify-center rounded-2xl w-40 h-10 mb-4 bg-primary">
        <Link href={"/"}>Back to Home</Link>
      </div>

      <div className="flex rounded-xl">
        <div className="w-full max-w-lg self-center rounded-2xl mb-8">
          <Image src={episode.image} alt={episode.titleEpi} width={400} height={400} className="object-cover" />
        </div>
        <div className="w-full max-w-1xl flex flex-col mb-8 gap-4">
          <div className="flex gap-2 flex-wrap">
            {badges.map((badge) => (
              <span key={badge} className="px-3 py-1 bg-gray-100 text-gray-800 rounded-full text-sm">
                {badge}
              </span>
            ))}
          </div>
          <p className="text-sm text-gray-500 uppercase tracking-widest">
            {episode.titlePodcast} · Episode {episode.episodeNr}
          </p>
          <h1 className="text-3xl font-bold">{episode.titleEpi}</h1>
          <p className="text-base leading-relaxed mt-2">{episode.description}</p>
          <div className="flex gap-20 text-sm">
            <span>{episode.duration}</span>
            <span>{episode.date}</span>
          </div>
        </div>
      </div>

      {/* Client-Komponente übernimmt alles Interaktive */}
      <PodcastDetailClient
        src="/sample-3s.mp3"
        episodeId={episode.id}
        chapters={chapters}
        emotionData={emotionData}
      />

      {/* Empfohlene Episoden */}
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