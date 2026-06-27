"use client";
import { Search } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTransition } from "react";

type SearchType = "episode" | "chapter" | "podcast";

const FILTER_OPTIONS: { label: string; value: SearchType }[] = [
  { label: "Episoden",  value: "episode"  },
  { label: "Chapters",  value: "chapter"  },
  { label: "Podcasts",  value: "podcast"  },
];

type SearchBarProps = {
  placeholder?: string;
};

export function SearchBar({ placeholder = "Suche..." }: SearchBarProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  const currentType = (searchParams.get("type") as SearchType) ?? "episode";

  const updateParams = (q?: string, type?: SearchType) => {
    const params = new URLSearchParams(searchParams.toString());
    if (q !== undefined) {
      if (q) params.set("q", q);
      else   params.delete("q");
    }
    if (type) params.set("type", type);
    params.delete("page");
    startTransition(() => {
      router.replace(`/suche?${params.toString()}`);
    });
  };

  return (
    <div className="flex flex-col gap-3 w-full max-w-md">
      {/* Suchfeld */}
      <div className="relative w-full">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-foreground-subtle"
          size={18}
          aria-hidden="true"
        />
        <input
          type="search"
          value={searchParams.get("q") ?? ""}
          onChange={(e) => updateParams(e.target.value, undefined)}
          placeholder={placeholder}
          className="w-full rounded-2xl border border-border bg-background-card py-3 pl-10 pr-4 text-sm text-foreground outline-none transition placeholder:text-foreground-subtle focus:border-border-strong focus:bg-background-raised"
        />
      </div>

      {/* Filter-Tabs */}
      <div className="flex gap-2">
        {FILTER_OPTIONS.map((opt) => (
          <button
            key={opt.value}
            onClick={() => updateParams(undefined, opt.value)}
            className={`px-3 py-1.5 rounded-full text-xs font-medium border transition-all cursor-pointer
              ${currentType === opt.value
                ? "bg-primary-muted border-primary text-foreground"
                : "bg-background-card border-border text-foreground-subtle hover:bg-background-raised hover:border-border-strong"
              }`}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}