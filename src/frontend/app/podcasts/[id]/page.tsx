import { foundPodcast } from "@/lib/dummyData";
import { notFound } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import EmotionChart from "@/components/ui/chart";
import PodcastPlayer from "@/components/ui/podcastplayer";
import { FactCheckCard } from "@/components/ui/factcheck";

export default async function PodcastDetail({ params }: { params: { id: string } }) {
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

  const topics = [
    { name: "Test", summary: "kasgFLSIUGVÖq regwiucqwi ewbeöiaeivevcäcgä3iuvawevkeqräogirwa", start: 12, end: 15 },
  ];

  // Später aus der API befüllen
  const factChecks = [
    {
      verdict: "true" as const,
      explanation: "Die genannte Studie existiert und wurde 2023 im Fachjournal Nature veröffentlicht.",
      source: "https://nature.com/articles/example",
    },
    {
      verdict: "misleading" as const,
      explanation: "Die Aussage ist teilweise korrekt, lässt jedoch wichtigen Kontext weg.",
      source: "https://example.com/source",
    },
  ];

  return (
    <div className="min-h-screen flex flex-col px-4 py-12">
      {/* Back Button */}
      <div className="flex items-center justify-center rounded-2xl w-40 h-10 mb-4 bg-primary">
        <Link href={"/"}>Back to Home</Link>
      </div>

      {/* Hero: Bild + Metadaten */}
      <div className="flex">
        <div className="w-full max-w-2xl self-center rounded-2xl mb-8">
          <Image src={episode.image} alt={episode.titleEpi} width={400} height={400} className="object-cover" />
        </div>
        <div className="w-full self-center max-w-1xl flex flex-col gap-4">
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
          <div className="flex gap-6 text-sm">
            <span>{episode.duration}</span>
            <span>{episode.date}</span>
          </div>
        </div>
      </div>

      {/* Player + Analyse */}
      <div className="flex flex-row gap-6 w-full bg-background-raised mt-6 px-4 py-6">

        {/* Links: Player → Chart → Themen | Faktencheck */}
        <div className="flex-1">
          <PodcastPlayer
            src="/sample-3s.mp3"
            topics={topics}
            factChecks={factChecks.map((fc, index) => (
              <FactCheckCard key={index} factCheck={fc} />
            ))}
          >
            <EmotionChart data={emotionData} />
          </PodcastPlayer>
        </div>

        {/* Rechts: Konfigurationsmenü */}
        <div className="w-64 shrink-0">
          <p>Menü zum Konfigurieren</p>
        </div>

      </div>
    </div>
  );
}