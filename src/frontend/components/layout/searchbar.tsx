"use client";
import { Search } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, useRef, useTransition } from "react";

type SearchType = "episode" | "chapter" | "podcast";

const FILTER_OPTIONS: { label: string; value: SearchType }[] = [
  { label: "Episoden",  value: "episode"  },
  { label: "Chapters",  value: "chapter"  },
  { label: "Podcasts",  value: "podcast"  },
];

type SearchBarProps = {
  placeholder?: string;
  defaultValue?: string;
  defaultType?: SearchType;
  autoFocus?: boolean;
};

export function SearchBar({
  placeholder = "Suche...",
  defaultValue = "",
  defaultType = "episode",
  autoFocus = false,
}: SearchBarProps) {
  const router = useRouter();
  const [, startTransition] = useTransition();

  const [value, setValue] = useState(defaultValue);
  const [currentType, setCurrentType] = useState<SearchType>(defaultType);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const navigate = (q: string, type: SearchType) => {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    if (type !== "episode") params.set("type", type);
    startTransition(() => {
      router.replace(`/suche?${params.toString()}`);
    });
  };

  const handleChange = (next: string) => {
    setValue(next);

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      navigate(next, currentType);
    }, 300);
  };

  const handleTypeChange = (type: SearchType) => {
    setCurrentType(type);
    navigate(value, type);
  };

  return (
    <div className="flex flex-col gap-3 w-full max-w-md">
      <div className="relative w-full">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-foreground-subtle"
          size={18}
          aria-hidden="true"
        />
        <input
          type="search"
          value={value}
          onChange={(e) => handleChange(e.target.value)}
          placeholder={placeholder}
          autoFocus={autoFocus}
          className="w-full rounded-2xl border border-border bg-background-card py-3 pl-10 pr-4 text-sm text-foreground outline-none transition placeholder:text-foreground-subtle focus:border-border-strong focus:bg-background-raised"
        />
      </div>

      {/* Filter-Tabs */}
      <div className="flex gap-2">
        {FILTER_OPTIONS.map((opt) => (
          <button
            key={opt.value}
            onClick={() => handleTypeChange(opt.value)}
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
