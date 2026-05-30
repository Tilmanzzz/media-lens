import { foundPodcast } from "@/lib/dummyData";
import { SearchBar } from "@/components/layout/searchbar";
import Image from "next/image";
import Link from "next/link";

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; page?: string }>
}) {
  const { q, page: pageParam } = await searchParams;
  const query = q?.toLowerCase() ?? "";

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

  // Episoden filtern
  const episodes = foundPodcast.filter(
    (p) =>
      p.titleEpi.toLowerCase().includes(query) ||
      p.description.toLowerCase().includes(query) ||
      p.badge?.toLowerCase().includes(query)
  );

  // Podcasts (einzigartige Podcast-Titel) filtern
  const podcastMap = new Map<string, typeof foundPodcast[0]>();
  foundPodcast.forEach((p) => {
    if (p.titlePodcast.toLowerCase().includes(query) && !podcastMap.has(p.titlePodcast)) {
      podcastMap.set(p.titlePodcast, p);
    }
  });
  const podcasts = Array.from(podcastMap.values());

  const total = episodes.length + podcasts.length;

  // Bestes Ergebnis = erstes Episodenergebnis
  const topResult = episodes[0] ?? podcasts[0] ?? null;

  return (
    <div className="mx-auto max-w-7xl px-4 py-8">
      {/* Suchleiste */}
      <div className="max-w-md mb-8">
        <SearchBar placeholder="Suche nach Episoden oder Podcasts..." />
      </div>

      {/* Meta */}
      <p className="text-sm text-foreground-subtle mb-6">
        <span className="text-foreground font-medium">{total}</span> Ergebnisse für{" "}
        <span className="text-foreground font-medium">„{searchParams.q}"</span>
      </p>

      {total === 0 ? (
        <p className="text-sm text-foreground-subtle">Keine Ergebnisse gefunden.</p>
      ) : (
        <div className="flex flex-col gap-10">

          {/* Bestes Ergebnis + erste Episoden */}
          {topResult && (
            <div className="grid grid-cols-1 lg:grid-cols-[280px_1fr] gap-6">
              {/* Bestes Ergebnis */}
              <div>
                <p className="text-base font-medium text-foreground mb-4">Bestes Ergebnis</p>
                <Link
                  href={`/podcasts/${topResult.id}`}
                  className="flex flex-col gap-4 bg-background-card hover:bg-background-raised border border-border rounded-xl p-5 transition-colors"
                >
                  <div className="relative w-24 h-24 rounded-lg overflow-hidden shrink-0">
                    <Image src={topResult.image} alt={topResult.titleEpi} fill className="object-cover" />
                  </div>
                  <div>
                    <p className="text-lg font-semibold text-foreground line-clamp-2">{topResult.titleEpi}</p>
                    <p className="text-sm text-foreground-subtle mt-1">
                      Episode {topResult.episodeNr} · {topResult.titlePodcast}
                    </p>
                    {topResult.badge && (
                      <span className="mt-2 inline-block text-xs px-2.5 py-1 rounded-full bg-primary-muted text-primary">
                        {topResult.badge}
                      </span>
                    )}
                  </div>
                </Link>
              </div>

              {/* Episoden-Liste */}
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
                          <Image src={ep.image} alt={ep.titleEpi} fill className="object-cover" />
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-medium text-foreground truncate">{ep.titleEpi}</p>
                          <p className="text-xs text-foreground-subtle truncate">
                            {ep.titlePodcast} · Episode {ep.episodeNr}
                          </p>
                        </div>
                        <span className="text-xs text-foreground-subtle">{ep.duration}</span>
                      </Link>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Alle Episoden */}
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
                      <Image src={ep.image} alt={ep.titleEpi} fill className="object-cover" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{ep.titleEpi}</p>
                      <p className="text-xs text-foreground-subtle truncate">
                        {ep.titlePodcast} · Episode {ep.episodeNr}
                      </p>
                    </div>
                    <span className="text-xs text-foreground-subtle">{ep.duration}</span>
                  </Link>
                ))}
              </div>
            </div>
          )}

          {/* Podcasts Grid */}
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
                      <Image
                        src={p.image}
                        alt={p.titlePodcast}
                        fill
                        className="object-cover group-hover:opacity-80 transition-opacity"
                      />
                    </div>
                    <p className="text-sm font-medium text-foreground truncate">{p.titlePodcast}</p>
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