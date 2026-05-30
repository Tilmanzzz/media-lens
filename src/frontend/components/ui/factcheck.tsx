import type { FactCheckedClaim, FactVerdict } from "@/lib/types";

interface FactCheckCardProps {
  claim: FactCheckedClaim;
}

const verdictConfig: Record<FactVerdict, { label: string; bg: string; border: string; text: string }> = {
  TRUE:         { label: "Wahr",          bg: "bg-success-bg",      border: "border-success",  text: "text-success"  },
  MOSTLY_TRUE:  { label: "Überwiegend wahr", bg: "bg-success-bg",   border: "border-success",  text: "text-success"  },
  MISLEADING:   { label: "Irreführend",   bg: "bg-warning-bg",      border: "border-warning",  text: "text-warning"  },
  FALSE:        { label: "Falsch",        bg: "bg-danger-bg",       border: "border-danger",   text: "text-danger"   },
  UNVERIFIABLE: { label: "Unprüfbar",     bg: "bg-background-card", border: "border-border",   text: "text-foreground-subtle" },
};

export function FactCheckCard({ claim }: FactCheckCardProps) {
  const config = verdictConfig[claim.verdict];

  return (
    <div className={`rounded-xl p-4 border ${config.bg} ${config.border}`}>
      {/* Verdict Badge */}
      <span className={`inline-block text-xs font-semibold px-2.5 py-1 rounded-full border mb-3 ${config.text} ${config.border}`}>
        {config.label}
      </span>

      {/* Claim */}
      {claim.claim && (
        <p className="text-xs font-medium text-foreground mb-1">
          „{claim.claim}
        </p>
      )}

      {/* Explanation */}
      {claim.explanation && (
        <p className="text-xs text-foreground-subtle leading-relaxed mb-3">
          {claim.explanation}
        </p>
      )}

      {/* Sources */}
      {claim.sources && claim.sources.length > 0 && (
        <div className="flex flex-col gap-1">
          {claim.sources.map((source, i) => (
            <div key={i} className="flex items-center gap-1.5">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-foreground-subtle shrink-0">
                <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
                <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
              </svg>
              <a
                href={source}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-foreground-muted hover:text-accent transition-colors truncate"
              >
                {source}
              </a>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}