"use client";

import { foundPodcast } from "@/lib/dummyData";
import { InfoCard } from "@/components/ui/card";
import { useState } from "react";
import { SearchBar } from "@/components/layout/searchbar";


export default function HomePage() {
  const [search, setSearch] = useState("");
  return (
    <div className="mx-auto max-w-7xl">
      <header className="mb-8">
         <div className="mt-3">
            <SearchBar value={search} onChange={setSearch} />
          </div>
        <h1 className=" mt-10 text-3xl font-bold text-foreground">Discover Podcasts</h1>
        <p className="mt-2 text-sm text-foreground">
          {foundPodcast?.length ?? 0} Podcasts gefunden
        </p>
      </header>

      <section>
        <div className="grid gap-6 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {foundPodcast.map((item) => (
            <InfoCard key={item.id} {...item} />
          ))}
        </div>
      </section>
    </div>
  );
}