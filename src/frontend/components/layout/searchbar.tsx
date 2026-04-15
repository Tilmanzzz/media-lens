import { Search } from "lucide-react";

type SearchBarProps = {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
};

export function SearchBar({
  value,
  onChange,
  placeholder = "Suche...",
}: SearchBarProps) {
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
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-2xl border border-border bg-background-card py-3 pl-10 pr-4 text-sm text-foreground outline-none transition placeholder:text-foreground-subtle focus:border-border-strong focus:bg-background-raised"
      />
    </div>
  );
}