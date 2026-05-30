"use client";

import { Search } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTransition } from "react";

type SearchBarProps = {
  placeholder?: string;
};

export function SearchBar({ placeholder = "Suche..." }: SearchBarProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  const handleChange = (value: string) => {
    const params = new URLSearchParams(searchParams.toString());
    if (value) {
      params.set("q", value);
    } else {
      params.delete("q");
    }
    params.delete("page"); // bei neuer Suche zurück auf Seite 1
    startTransition(() => {
      router.replace(`/suche?${params.toString()}`);
    });
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
        defaultValue={searchParams.get("q") ?? ""}
        onChange={(e) => handleChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-2xl border border-border bg-background-card py-3 pl-10 pr-4 text-sm text-foreground outline-none transition placeholder:text-foreground-subtle focus:border-border-strong focus:bg-background-raised"
      />
    </div>
  );
}