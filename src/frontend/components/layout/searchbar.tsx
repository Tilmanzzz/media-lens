"use client";

import { Search } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, useRef, useTransition } from "react";

type SearchBarProps = {
  placeholder?: string;
  defaultValue?: string;
  autoFocus?: boolean;
};

export function SearchBar({ placeholder = "Suche...", defaultValue = "", autoFocus = false }: SearchBarProps) {
  const router = useRouter();
  const [, startTransition] = useTransition();

  const [value, setValue] = useState(defaultValue);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleChange = (next: string) => {
    setValue(next);

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      const params = new URLSearchParams();
      if (next) {
        params.set("q", next);
      }
      startTransition(() => {
        router.replace(`/suche?${params.toString()}`);
      });
    }, 300);
  };

  return (
    <div className="relative w-full max-w-md">
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
  );
}