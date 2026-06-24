import { fetchEpisodes } from "@/lib/api";
import type { EpisodeCard } from "@/lib/types";
import { SearchBar } from "@/components/layout/searchbar";
import Image from "next/image";
import Link from "next/link";

function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

export default async function SearchPage({
  searchParams,
}: {
  searchParams: { q?: string };
}) {
  const query = searchParams.q ?? "";
  
  if (!query) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-12">
        <div className="max-w-md mb-8">
          <SearchBar placeholder="Suche nach Episoden oder Podcasts..." />
        </div>
        <p className="text-sm text-foreground-subtle">Gib einen Suchbegriff ein.</p>
      </div>
    );
  }

  const { items: episodes, total } = await fetchEpisodes({ q: query, limit: 50 });

  const podcastMap = new Map<string, EpisodeCard>();
  for (const ep of episodes) {
    if (!podcastMap.has(ep.podcast_name)) {
      podcastMap.set(ep.podcast_name, ep);
    }
  }
  const podcasts = Array.from(podcastMap.values());

  const topResult = episodes[0] ?? null;

  return (
    <div className="mx-auto max-w-7xl px-4 py-8">
      <div className="max-w-md mb-8">
        <SearchBar placeholder="Suche nach Episoden oder Podcasts..." />
      </div>

      <p className="text-sm text-foreground-subtle mb-6">
        <span className="text-foreground font-medium">{total}</span> Ergebnisse für{" "}
        <span className="text-foreground font-medium">„{q}"</span>
      </p>

      {episodes.length === 0 ? (
        <p className="text-sm text-foreground-subtle">Keine Ergebnisse gefunden.</p>
      ) : (
        <div className="flex flex-col gap-10">

          {topResult && (
            <div className="grid grid-cols-1 lg:grid-cols-[280px_1fr] gap-6">
              <div>
                <p className="text-base font-medium text-foreground mb-4">Bestes Ergebnis</p>
                <Link
                  href={`/podcasts/${topResult.id}`}
                  className="flex flex-col gap-4 bg-background-card hover:bg-background-raised border border-border rounded-xl p-5 transition-colors"
                >
                  <div className="relative w-24 h-24 rounded-lg overflow-hidden shrink-0">
                    {topResult.cover_url ? (
                      <Image src={topResult.cover_url} alt={topResult.title} fill className="object-cover" />
                    ) : (
                      <div className="w-full h-full bg-background-card flex items-center justify-center">
                        <span className="text-foreground-subtle text-xs">Kein Cover</span>
                      </div>
                    )}
                  </div>
                  <div>
                    <p className="text-lg font-semibold text-foreground line-clamp-2">{topResult.title}</p>
                    <p className="text-sm text-foreground-subtle mt-1">{topResult.podcast_name}</p>
                  </div>
                </Link>
              </div>

              {episodes.length > 0 && (
                <div>
                  <p className="text-base font-medium text-foreground mb-4">Episoden</p>
                  <div className="flex flex-col gap-0.5">
                    {episodes.slice(0, 5).map((ep, index) => (
                      <Link
                        key={ep.id}
                        href={`/podcasts/${ep.id}`}
                        className="grid grid-cols-[32px_48px_1fr_auto] items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-background-card transition-colors group"
                      >
                        <span className="text-sm text-foreground-subtle text-center group-hover:hidden">
                          {index + 1}
                        </span>
                        <span className="text-sm text-foreground-subtle text-center hidden group-hover:block">
                          ▶
                        </span>
                        <div className="relative w-12 h-12 rounded overflow-hidden shrink-0">
                          {ep.cover_url ? (
                            <Image src={ep.cover_url} alt={ep.title} fill className="object-cover" />
                          ) : (
                            <div className="w-full h-full bg-background-card flex items-center justify-center">
                              <span className="text-foreground-subtle text-[10px]">Kein Cover</span>
                            </div>
                          )}
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-medium text-foreground truncate">{ep.title}</p>
                          <p className="text-xs text-foreground-subtle truncate">{ep.podcast_name}</p>
                        </div>
                        <span className="text-xs text-foreground-subtle">{formatDuration(ep.duration_seconds)}</span>
                      </Link>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {episodes.length > 5 && (
            <div>
              <p className="text-base font-medium text-foreground mb-4">
                Alle Episoden
                <span className="ml-2 text-sm text-foreground-subtle font-normal">({episodes.length})</span>
              </p>
              <div className="flex flex-col gap-0.5">
                {episodes.slice(5).map((ep) => (
                  <Link
                    key={ep.id}
                    href={`/podcasts/${ep.id}`}
                    className="grid grid-cols-[48px_1fr_auto] items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-background-card transition-colors group"
                  >
                    <div className="relative w-12 h-12 rounded overflow-hidden shrink-0">
                      {ep.cover_url ? (
                        <Image src={ep.cover_url} alt={ep.title} fill className="object-cover" />
                      ) : (
                        <div className="w-full h-full bg-background-card flex items-center justify-center">
                          <span className="text-foreground-subtle text-[10px]">Kein Cover</span>
                        </div>
                      )}
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{ep.title}</p>
                      <p className="text-xs text-foreground-subtle truncate">{ep.podcast_name}</p>
                    </div>
                    <span className="text-xs text-foreground-subtle">{formatDuration(ep.duration_seconds)}</span>
                  </Link>
                ))}
              </div>
            </div>
          )}

          {podcasts.length > 0 && (
            <div>
              <p className="text-base font-medium text-foreground mb-4">
                Podcasts
                <span className="ml-2 text-sm text-foreground-subtle font-normal">({podcasts.length})</span>
              </p>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                {podcasts.map((p) => (
                  <Link
                    key={p.id}
                    href={`/podcasts/${p.id}`}
                    className="flex flex-col gap-2 group"
                  >
                    <div className="relative w-full aspect-square rounded-lg overflow-hidden">
                      {p.cover_url ? (
                        <Image
                          src={p.cover_url}
                          alt={p.podcast_name}
                          fill
                          className="object-cover group-hover:opacity-80 transition-opacity"
                        />
                      ) : (
                        <div className="w-full h-full bg-background-card flex items-center justify-center">
                          <span className="text-foreground-subtle text-xs">Kein Cover</span>
                        </div>
                      )}
                    </div>
                    <p className="text-sm font-medium text-foreground truncate">{p.podcast_name}</p>
                    <p className="text-xs text-foreground-subtle">Podcast</p>
                  </Link>
                ))}
              </div>
            </div>
          )}

        </div>
      )}
    </div>
  );
}
