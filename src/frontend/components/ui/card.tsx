// components/deep-dive-card.tsx
import Image from "next/image";

type DeepDiveCardProps = {
  title: string;
  description: string;
  image: string;
  href: string;
  badge?: string;
  duration?: string;
};

export function DeepDiveCard({
  title,
  description,
  image,
  href,
  badge,
  duration,
}: DeepDiveCardProps) {
  return (
    <a
      href={href}
      className="group block overflow-hidden rounded-2xl bg-[var(--background-card)] transition hover:scale-[1.02] hover:bg-white/5"
    >
      {/* Bild mit fester Höhe */}
      <div className="relative h-[160px] w-full">
        <Image
          src={image}
          alt={title}
          fill
          className="object-cover"
        />
      </div>

      {/* Text */}
      <div className="p-4">
        {badge && (
          <span className="mb-2 inline-block rounded-full bg-[var(--accent)] px-2 py-0.5 text-xs font-medium text-black">
            {badge}
          </span>
        )}
        <h3 className="text-lg font-semibold">{title}</h3>
        <p className="mt-1 line-clamp-2 text-sm text-white/60">
          {description}
        </p>
        {duration && (
          <p className="mt-3 text-xs text-white/40">
            {duration}
          </p>
        )}
      </div>
    </a>
  );
}