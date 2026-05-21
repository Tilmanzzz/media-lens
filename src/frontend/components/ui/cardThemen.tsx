"use client";

interface Topic {
  name: string;
  summary: string;
  start: number;
  end: number;
}

interface TopicCardProps {
  topic: Topic;
  isActive: boolean;
  onSelect: (start: number) => void;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function TopicCard({ topic, isActive, onSelect }: TopicCardProps) {
  const duration = topic.end - topic.start;

  return (
    <button
      onClick={() => onSelect(topic.start)}
      className={`w-full text-left rounded-xl p-4 border transition-all cursor-pointer
        ${isActive
          ? "bg-accent-muted border-border-accent"
          : "bg-background-card border-border hover:bg-background-raised hover:border-border-strong"
        }`}
    >
      {/* Name + Zeitspanne */}
      <div className="flex items-start justify-between gap-3 mb-2">
        <span className={`font-medium text-sm ${isActive ? "text-accent" : "text-foreground"}`}>
          {topic.name}
        </span>
        <span className="text-xs text-foreground-subtle whitespace-nowrap shrink-0">
          {formatTime(topic.start)} – {formatTime(topic.end)}
        </span>
      </div>

      {/* Zusammenfassung */}
      <p className="text-xs text-foreground-subtle leading-relaxed mb-3">
        {topic.summary}
      </p>

      {/* Gesamtdauer */}
      <div className="flex items-center gap-1.5">
        <svg
          width="12" height="12" viewBox="0 0 24 24"
          fill="none" stroke="currentColor" strokeWidth="2"
          strokeLinecap="round" strokeLinejoin="round"
          className="text-foreground-subtle"
        >
          <circle cx="12" cy="12" r="10" />
          <polyline points="12 6 12 12 16 14" />
        </svg>
        <span className="text-xs text-foreground-subtle">{formatTime(duration)}</span>
      </div>
    </button>
  );
}