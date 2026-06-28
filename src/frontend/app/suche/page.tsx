import { fetchSearch } from "@/lib/api";
import type { SearchResultItem } from "@/lib/types";
import { SearchBar } from "@/components/layout/searchbar";
import Image from "next/image";
import Link from "next/link";

function formatTimestamp(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

type SearchType = "episode" | "chapter" | "podcast";

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; type?: string }>;
}) {
  const { q: query = "", type: rawType } = await searchParams;
  const type = (rawType as SearchType) ?? null;

  const hasQuery = query.length > 0;
  const { items: results, total } = hasQuery
    ? await fetchSearch({ q: query, limit: 20, highlights: 3 })
    : { items: [] as SearchResultItem[], total: 0 };

  const podcastMap = new Map<string, SearchResultItem>();
  for (const r of results) {
    if (!podcastMap.has(r.podcast_name)) {
      podcastMap.set(r.podcast_name, r);
    }
  }
  const podcasts = Array.from(podcastMap.values());

  const topResult = results[0] ?? null;

  const showEpisodes = !type || type === "episode";
  const showChapters = !type || type === "chapter";
  const showPodcasts = !type || type === "podcast";

  const allHighlights = results.flatMap((r) =>
    r.highlights.map((h) => ({ ...h, episode_id: r.episode_id, title: r.title, podcast_name: r.podcast_name, cover_url: r.cover_url }))
  );

  return (
    <div className="mx-auto max-w-7xl px-4 py-8">
      <div className="max-w-md mb-8">
        <SearchBar
          placeholder="Suche nach Episoden oder Podcasts..."
          defaultValue={query}
          defaultType={type}
          autoFocus
        />
      </div>

      {!hasQuery ? (
        <p className="text-sm text-foreground-subtle">Gib einen Suchbegriff ein.</p>
      ) : (
        <>
          <p className="text-sm text-foreground-subtle mb-6">
            <span className="text-foreground font-medium">{total}</span> Ergebnisse für{" "}
            <span className="text-foreground font-medium">„{query}"</span>
          </p>

          {results.length === 0 ? (
            <p className="text-sm text-foreground-subtle">Keine Ergebnisse gefunden.</p>
          ) : (
            <div className="flex flex-col gap-10">

          {/* ── Default-Ansicht (kein Filter): Bestes Ergebnis + Top 5 + Rest + Chapters + Podcasts ── */}
          {!type && topResult && (
            <div className="grid grid-cols-1 lg:grid-cols-[280px_1fr] gap-6">
              <div>
                <p className="text-base font-medium text-foreground mb-4">Bestes Ergebnis</p>
                <Link
                  href={`/podcasts/${topResult.episode_id}`}
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
                    {topResult.highlights.length > 0 && (
                      <p className="text-xs text-foreground-subtle mt-2 line-clamp-2 italic">
                        „{topResult.highlights[0].text}"
                      </p>
                    )}
                  </div>
                </Link>
              </div>

              {results.length > 0 && (
                <div>
                  <p className="text-base font-medium text-foreground mb-4">Episoden</p>
                  <div className="flex flex-col gap-0.5">
                    {results.slice(0, 5).map((r, index) => (
                      <Link
                        key={r.episode_id}
                        href={`/podcasts/${r.episode_id}`}
                        className="grid grid-cols-[32px_48px_1fr] items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-background-card transition-colors group"
                      >
                        <span className="text-sm text-foreground-subtle text-center group-hover:hidden">
                          {index + 1}
                        </span>
                        <span className="text-sm text-foreground-subtle text-center hidden group-hover:block">
                          ▶
                        </span>
                        <div className="relative w-12 h-12 rounded overflow-hidden shrink-0">
                          {r.cover_url ? (
                            <Image src={r.cover_url} alt={r.title} fill className="object-cover" />
                          ) : (
                            <div className="w-full h-full bg-background-card flex items-center justify-center">
                              <span className="text-foreground-subtle text-[10px]">Kein Cover</span>
                            </div>
                          )}
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm font-medium text-foreground truncate">{r.title}</p>
                          <p className="text-xs text-foreground-subtle truncate">{r.podcast_name}</p>
                          {r.highlights.length > 0 && (
                            <p className="text-xs text-foreground-subtle truncate italic">
                              {formatTimestamp(r.highlights[0].start_time)} – „{r.highlights[0].text}"
                            </p>
                          )}
                        </div>
                      </Link>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {!type && results.length > 5 && (
            <div>
              <p className="text-base font-medium text-foreground mb-4">
                Alle Episoden
                <span className="ml-2 text-sm text-foreground-subtle font-normal">({results.length})</span>
              </p>
              <div className="flex flex-col gap-0.5">
                {results.slice(5).map((r) => (
                  <Link
                    key={r.episode_id}
                    href={`/podcasts/${r.episode_id}`}
                    className="grid grid-cols-[48px_1fr] items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-background-card transition-colors group"
                  >
                    <div className="relative w-12 h-12 rounded overflow-hidden shrink-0">
                      {r.cover_url ? (
                        <Image src={r.cover_url} alt={r.title} fill className="object-cover" />
                      ) : (
                        <div className="w-full h-full bg-background-card flex items-center justify-center">
                          <span className="text-foreground-subtle text-[10px]">Kein Cover</span>
                        </div>
                      )}
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{r.title}</p>
                      <p className="text-xs text-foreground-subtle truncate">{r.podcast_name}</p>
                      {r.highlights.length > 0 && (
                        <p className="text-xs text-foreground-subtle truncate italic">
                          {formatTimestamp(r.highlights[0].start_time)} – „{r.highlights[0].text}"
                        </p>
                      )}
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          )}

          {/* ── Filter: nur Episoden ── */}
          {type === "episode" && results.length > 0 && (
            <div>
              <p className="text-base font-medium text-foreground mb-4">
                Episoden
                <span className="ml-2 text-sm text-foreground-subtle font-normal">({results.length})</span>
              </p>
              <div className="flex flex-col gap-0.5">
                {results.map((r) => (
                  <Link
                    key={r.episode_id}
                    href={`/podcasts/${r.episode_id}`}
                    className="grid grid-cols-[48px_1fr] items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-background-card transition-colors group"
                  >
                    <div className="relative w-12 h-12 rounded overflow-hidden shrink-0">
                      {r.cover_url ? (
                        <Image src={r.cover_url} alt={r.title} fill className="object-cover" />
                      ) : (
                        <div className="w-full h-full bg-background-card flex items-center justify-center">
                          <span className="text-foreground-subtle text-[10px]">Kein Cover</span>
                        </div>
                      )}
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{r.title}</p>
                      <p className="text-xs text-foreground-subtle truncate">{r.podcast_name}</p>
                      {r.highlights.length > 0 && (
                        <p className="text-xs text-foreground-subtle truncate italic">
                          {formatTimestamp(r.highlights[0].start_time)} – „{r.highlights[0].text}"
                        </p>
                      )}
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          )}

          {/* ── Filter: nur Chapters / Default: Chapters-Sektion ── */}
          {showChapters && allHighlights.length > 0 && (
            <div>
              <p className="text-base font-medium text-foreground mb-4">
                Chapters
                <span className="ml-2 text-sm text-foreground-subtle font-normal">({allHighlights.length})</span>
              </p>
              <div className="flex flex-col gap-0.5">
                {allHighlights.map((h, index) => (
                  <Link
                    key={`${h.episode_id}-${h.start_time}-${index}`}
                    href={`/podcasts/${h.episode_id}`}
                    className="grid grid-cols-[48px_1fr] items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-background-card transition-colors"
                  >
                    <div className="relative w-12 h-12 rounded overflow-hidden shrink-0">
                      {h.cover_url ? (
                        <Image src={h.cover_url} alt={h.title} fill className="object-cover" />
                      ) : (
                        <div className="w-full h-full bg-background-card flex items-center justify-center">
                          <span className="text-foreground-subtle text-[10px]">Kein Cover</span>
                        </div>
                      )}
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{h.title}</p>
                      <p className="text-xs text-foreground-subtle truncate">{h.podcast_name}</p>
                      <p className="text-xs text-foreground-subtle truncate italic">
                        {formatTimestamp(h.start_time)} – „{h.text}"
                      </p>
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          )}

          {/* ── Filter: nur Podcasts / Default: Podcasts-Sektion ── */}
          {showPodcasts && podcasts.length > 0 && (
            <div>
              <p className="text-base font-medium text-foreground mb-4">
                Podcasts
                <span className="ml-2 text-sm text-foreground-subtle font-normal">({podcasts.length})</span>
              </p>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                {podcasts.map((p) => (
                  <Link
                    key={p.episode_id}
                    href={`/podcasts/${p.episode_id}`}
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
        </>
      )}
    </div>
  );
}
