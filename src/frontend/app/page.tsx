import { fetchEpisodes } from "@/lib/api";
import { InfoCard } from "@/components/ui/card";
import { SearchBar } from "@/components/layout/searchbar";
import Link from "next/link";

export default async function HomePage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string }>;
}) {
  const { q, cursor } = await searchParams;
  const query = q ?? "";

  const { items, next_cursor, total } = await fetchEpisodes({
    q: query || undefined,
    cursor: cursor || undefined,
    limit: 8,
  });

  function buildHref(c?: string | null) {
    const params = new URLSearchParams();
    if (query) params.set("q", query);
    if (c) params.set("cursor", c);
    const qs = params.toString();
    return qs ? `?${qs}` : "/";
  }

  return (
    <div className="mx-auto max-w-7xl">
      <header className="mb-8">
        <div className="mt-3">
          <SearchBar placeholder="Suche..." />
        </div>
        <h1 className="mt-10 text-3xl font-bold text-foreground">Discover Podcasts</h1>
        <p className="mt-2 text-sm text-foreground-subtle">
          {total} {query ? `Ergebnisse für „${query}"` : "Podcasts gefunden"}
        </p>
      </header>

      <section>
        <div className="grid gap-6 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {items.length > 0 ? (
            items.map((item) => <InfoCard key={item.id} {...item} />)
          ) : (
            <p className="text-sm text-foreground-subtle col-span-full">Keine Podcasts gefunden.</p>
          )}
        </div>
      </section>

      {next_cursor && (
        <div className="mt-10 flex justify-center">
          <Link
            href={buildHref(next_cursor)}
            className="flex items-center justify-center px-5 h-9 rounded-lg border border-border bg-background-card text-foreground-subtle hover:bg-background-raised hover:text-foreground transition-colors text-sm"
          >
            Weiter →
          </Link>
        </div>
      )}
    </div>
  );
}
