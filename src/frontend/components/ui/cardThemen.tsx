"use client";

import { useState } from "react";

interface Topic {
  name: string;
  summary: string;
  start: number;
  end: number;
}

interface TopicCardProps {
  topic: Topic;
  isActive: boolean;
  isFiltered: boolean;
  onSelect: (start: number) => void;
  onFilterToggle: () => void;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function TopicCard({ topic, isActive, isFiltered, onSelect, onFilterToggle }: TopicCardProps) {
  const duration = topic.end - topic.start;
  const [clicked, setClicked] = useState(false);

  const handleSelect = () => {
    onSelect(topic.start);
    setClicked(true);
    setTimeout(() => setClicked(false), 600);
  };

  return (
    <div
      onClick={handleSelect}
      className={`w-full text-left rounded-xl p-4 border transition-all cursor-pointer
        ${isActive
          ? "bg-accent-muted border-border-accent"
          : clicked
            ? "bg-primary border-primary"
            : isFiltered
              ? "bg-primary-muted border-primary"
              : "bg-background-card border-border hover:bg-background-raised hover:border-border-strong"
        }`}
    >
      {/* Name + Zeitspanne */}
      <div className="flex items-start justify-between gap-3 mb-2">
        <span
          className={`font-medium text-sm ${isActive ? "text-accent" : "text-foreground"}`}
        >
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

      {/* Footer: Dauer + Fakten-Button */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-1.5">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-foreground-subtle">
            <circle cx="12" cy="12" r="10" />
            <polyline points="12 6 12 12 16 14" />
          </svg>
          <span className="text-xs text-foreground-subtle">{formatTime(duration)}</span>
        </div>

        <button
          onClick={(e) => { e.stopPropagation(); onFilterToggle(); }}
          className={`flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-full border transition-all cursor-pointer
            ${isFiltered
              ? "bg-primary-muted border-primary text-foreground-muted"
              : "bg-background-raised border-border text-foreground-subtle hover:border-border-strong hover:text-foreground"
            }`}
        >
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <path d="M9 11l3 3L22 4" />
            <path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
          </svg>
          {isFiltered ? "Fakten aktiv" : "Fakten zeigen"}
        </button>
      </div>
    </div>
  );
}