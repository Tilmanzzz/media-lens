import { foundPodcast } from "@/lib/dummyData";
import { notFound } from "next/navigation";
import { Image } from "lucide-react";
import Link from "next/link";
import AudioPlayer from "@/components/ui/audio";

export default async function PodcastDetail({ params }: { params: { id: string } }) {
  const { id } = await params;

  const episode = foundPodcast.find((p) => p.id === id);

  if (!episode) notFound();

  const badges = episode.badge.split(",").map((b) => b.trim());

  return (
    <div className="min-h-screen flex flex-col items-center px-4 py-12">

      <div className="bg-primary">
        <Link href={"/"} >Back to Home</Link>
      </div>
      
      <div className="w-full max-w-2xl rounded-2xl overflow-hidden mb-8">
        <Image src={episode.image} alt={episode.titleEpi} className="object-cover" />
      </div>

      <div className="w-full max-w-2xl flex flex-col gap-4">

        {/* Podcast-Titel & Episode Nr */}
        <p className="text-sm text-gray-500 uppercase tracking-widest">
          {episode.titlePodcast} · Episode {episode.episodeNr}
        </p>

        {/* Episodentitel */}
        <h1 className="text-3xl font-bold">{episode.titleEpi}</h1>

        {/* Badges */}
        <div className="flex gap-2 flex-wrap">
          {badges.map((badge) => (
            <span
              key={badge}
              className="px-3 py-1 bg-gray-100 text-gray-700 rounded-full text-sm"
            >
              {badge}
            </span>
          ))}
        </div>

        <div className="flex gap-6 text-sm text-gray-500">
          <span> {episode.duration}</span>
          <span> {episode.date}</span>
        </div>

        <p className="text-gray-700 text-base leading-relaxed mt-2">
          {episode.description}
        </p>

      </div>
      <div>
        <AudioPlayer src=""></AudioPlayer>
      </div>
    </div>
  );
}