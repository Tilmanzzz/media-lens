import { foundPodcast } from "@/lib/dummyData"; 
import { DeepDiveCard } from "@/components/ui/card";

export default function HomePage() {
  return (
    <div className="mx-auto max-w-6xl">
      <header className="mb-8">
        <h1 className="text-3xl font-bold"> Discover Podcasts</h1>
        <p className="mt-2 text-sm text-white/60">
          {foundPodcast?.length ?? 0} Podcasts gefunden
        </p>
      </header>

      <section>
        <div className="grid gap-6 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {foundPodcast.map((item) => (
            <DeepDiveCard
              key={item.id}
              title={item.title}
              description={item.description}
              image={item.image}
              href={item.href}
              badge={item.badge}
              duration={item.duration}
            />
          ))}
        </div>
      </section>
    </div>
  );
}