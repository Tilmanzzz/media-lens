import Image from "next/image";
import Link from "next/link";

type InfoCardProps = {
  id: string;
  title: string;
  podcast_name: string;
  published_at: string;
  cover_url: string;
  summary: string;
  duration_seconds: number;
};

function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) {
    return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  }
  return `${m}:${String(s).padStart(2, "0")}`;
}

export function InfoCard({
  id,
  title,
  podcast_name,
  published_at,
  cover_url,
  summary,
  duration_seconds,
}: InfoCardProps) {
  const formattedDate = new Date(published_at).toLocaleDateString("de-DE", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });

  return (
    <Link href={`/podcasts/${id}`} className="bg-primary-muted hover:bg-primary-hover shadow-xs rounded-xl">
      <div className="relative h-[170px] w-full bg-background-raised">
        {cover_url ? (
          <Image src={cover_url} alt={title} fill className="object-cover rounded-t-xl" />
        ) : (
          <div className="w-full h-full rounded-t-xl bg-background-card flex items-center justify-center">
            <span className="text-foreground-subtle text-xs">Kein Cover</span>
          </div>
        )}
      </div>
      <div className="p-4">
        <p className="mt-1 text-xs text-foreground-subtle">{podcast_name}</p>
        <h3 className="mt-1 text-xl font-semibold text-foreground">{title}</h3>
        <p className="mt-2 line-clamp-2 text-sm hover:text-primary-muted text-foreground-muted">
          {summary}
        </p>
        <div className="flex mt-3 items-center justify-between text-xs text-foreground-subtle">
          <span>{formattedDate}</span>
          <span>{formatDuration(duration_seconds)}</span>
        </div>
      </div>
    </Link>
  );
}
