interface FactCheck {
  verdict: "true" | "false" | "misleading" | "unverified";
  explanation: string;
  source: string;
}

interface FactCheckCardProps {
  factCheck: FactCheck;
}

const verdictConfig = {
  true:       { label: "Wahr",          bg: "bg-success-bg",  border: "border-success",  text: "text-success"  },
  false:      { label: "Falsch",        bg: "bg-danger-bg",   border: "border-danger",   text: "text-danger"   },
  misleading: { label: "Irreführend",   bg: "bg-warning-bg",  border: "border-warning",  text: "text-warning"  },
  unverified: { label: "Ungeprüft",     bg: "bg-background-card", border: "border-border", text: "text-foreground-subtle" },
};

export function FactCheckCard({ factCheck }: FactCheckCardProps) {
  const config = verdictConfig[factCheck.verdict];

  return (
    <div className={`rounded-xl p-4 border ${config.bg} ${config.border}`}>
      {/* Verdict Badge */}
      <span className={`inline-block text-xs font-semibold px-2.5 py-1 rounded-full border mb-3 ${config.text} ${config.border}`}>
        {config.label}
      </span>

      {/* Explanation */}
      <p className="text-sm text-foreground leading-relaxed mb-3">
        {factCheck.explanation}
      </p>

      {/* Source */}
      <div className="flex items-center gap-1.5">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-foreground-subtle shrink-0">
          <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
          <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
        </svg>
        <a
          href={factCheck.source}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-foreground-muted hover:text-accent transition-colors truncate"
        >
          {factCheck.source}
        </a>
      </div>
    </div>
  );
}