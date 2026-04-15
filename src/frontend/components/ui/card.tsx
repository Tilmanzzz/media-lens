import Image from "next/image";

type InfoCardProps = {
  episodeNr: number;
  titleEpi: string;
  description: string;
  titlePodcast: string;
  image: string;
  href: string;
  badge?: string;
  duration?: string;
  date: string;
};

export function InfoCard({
  episodeNr,
  titleEpi,
  description,
  titlePodcast,
  image,
  href,
  badge,
  duration,
  date
}: InfoCardProps) {
  return (
    <a
      href={href}
      className="group block overflow-hidden rounded-2xl border border-border bg-background-card transition duration-200 hover:-translate-y-0.5 hover:bg-background-raised hover:border-border-strong"
    >
      <div className="relative h-[170px] w-full">
        <Image src={image} alt={titleEpi} fill className="object-cover" />
      </div>

      <div className="p-4">
        <p className=" mt-1 text-xs text-foreground-subtle">Episode {episodeNr} - {titlePodcast}</p>
        <h3 className=" mt-1 text-xl font-semibold text-foreground">{titleEpi}</h3>
        <p className="mt-2 line-clamp-2 text-sm text-foreground-muted">
          {description}
        </p>
        <div className="flex mt-3 items-center justify-between text-sm text-foreground-muted">
            {badge && (
            <span className="mb-2 inline-flex rounded-full bg-primary-muted px-2.5 py-1 text-xs font-medium text-primary">
                {badge}
            </span>
            )}
            {duration && (
            <p className="mt-3 text-xs text-foreground-subtle">{duration}</p>
            )}
        </div>
      </div>
    </a>
  );
}