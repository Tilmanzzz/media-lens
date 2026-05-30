import { foundPodcast } from "@/lib/dummyData";
import { InfoCard } from "@/components/ui/card";
import { SearchBar } from "@/components/layout/searchbar";
import Link from "next/link";


const PAGE_SIZE = 8;

function Pagination({ page, totalPages, query }: { page: number; totalPages: number; query: string }) {
  const range = 2;
  const pages = Array.from({ length: totalPages }, (_, i) => i + 1).filter(
    (p) => p === 1 || p === totalPages || (p >= page - range && p <= page + range)
  );

  function buildHref(p: number) {
    const params = new URLSearchParams();
    if (query) params.set("q", query);
    params.set("page", String(p));
    return `?${params.toString()}`;
  }

  return (
    <div className="flex items-center justify-center gap-1">
      {page > 1 ? (
        <Link href={buildHref(page - 1)} className="flex items-center justify-center w-9 h-9 rounded-lg border border-border bg-background-card text-foreground-subtle hover:bg-background-raised hover:text-foreground transition-colors text-sm">‹</Link>
      ) : (
        <span className="flex items-center justify-center w-9 h-9 rounded-lg border border-border bg-background-card text-foreground-subtle opacity-40 text-sm cursor-not-allowed">‹</span>
      )}
      {pages.map((p, i) => {
        const prev = pages[i - 1];
        const showEllipsis = prev && p - prev > 1;
        return (
          <span key={p} className="flex items-center gap-1">
            {showEllipsis && (
              <span className="w-9 h-9 flex items-center justify-center text-foreground-subtle text-sm">…</span>
            )}
            <Link
              href={buildHref(p)}
              className={`flex items-center justify-center w-9 h-9 rounded-lg border text-sm transition-colors
                ${p === page
                  ? "bg-primary border-primary text-foreground font-medium"
                  : "border-border bg-background-card text-foreground-subtle hover:bg-background-raised hover:text-foreground"
                }`}
            >
              {p}
            </Link>
          </span>
        );
      })}
      {page < totalPages ? (
        <Link href={buildHref(page + 1)} className="flex items-center justify-center w-9 h-9 rounded-lg border border-border bg-background-card text-foreground-subtle hover:bg-background-raised hover:text-foreground transition-colors text-sm">›</Link>
      ) : (
        <span className="flex items-center justify-center w-9 h-9 rounded-lg border border-border bg-background-card text-foreground-subtle opacity-40 text-sm cursor-not-allowed">›</span>
      )}
    </div>
  );
}

export default async function HomePage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; page?: string }>;
}) {
  const { q, page: pageParam } = await searchParams;
  const query = q?.toLowerCase() ?? "";
  const page = Math.max(1, Number(pageParam ?? 1));

  const filtered = foundPodcast.filter((p) =>
    p.titleEpi.toLowerCase().includes(query) ||
    p.titlePodcast.toLowerCase().includes(query)
  );

  const total = filtered.length;
  const totalPages = Math.ceil(total / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  return (
    <div className="mx-auto max-w-7xl">
      <header className="mb-8">
        <div className="mt-3">
          <SearchBar placeholder="Suche..." />
        </div>
        <h1 className="mt-10 text-3xl font-bold text-foreground">Discover Podcasts</h1>
        <p className="mt-2 text-sm text-foreground-subtle">
          {total} {query ? `Ergebnisse für "${query}"` : "Podcasts gefunden"}
        </p>
      </header>

      <section>
        <div className="grid gap-6 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {paginated.length > 0 ? (
            paginated.map((item) => <InfoCard key={item.id} {...item} />)
          ) : (
            <p className="text-sm text-foreground-subtle col-span-full">Keine Podcasts gefunden.</p>
          )}
        </div>
      </section>

      {totalPages > 1 && (
        <div className="mt-10">
          <Pagination page={page} totalPages={totalPages} query={query} />
        </div>
      )}
    </div>
  );
}