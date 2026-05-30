"use client";

import { useEffect, useRef } from "react";
import type { TranscriptLine } from "@/lib/types";

interface TranscriptProps {
  lines: TranscriptLine[];
  currentTime: number;
  onLineClick: (start: number) => void;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export default function Transcript({ lines, currentTime, onLineClick }: TranscriptProps) {
  const activeRef = useRef<HTMLButtonElement | null>(null);

  const activeIndex = lines.findIndex(
    (l) => currentTime >= l.start_time && currentTime < l.end_time
  );

  useEffect(() => {
    activeRef.current?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }, [activeIndex]);

  return (
    <div className="flex flex-col gap-0.5 max-h-96 overflow-y-auto pr-2">
      {lines
        .sort((a, b) => a.line_idx - b.line_idx)
        .map((line, index) => {
          const isActive = index === activeIndex;
          return (
            <button
              key={line.id}
              ref={isActive ? activeRef : null}
              onClick={() => onLineClick(line.start_time)}
              className={`text-left px-3 py-2 rounded-lg text-sm transition-all cursor-pointer
                ${isActive
                  ? "bg-primary-muted text-foreground font-medium border-l-2 border-primary"
                  : "text-foreground-subtle hover:text-foreground hover:bg-background-card"
                }`}
            >
              <span className="text-xs mr-3 tabular-nums text-foreground-subtle">
                {formatTime(line.start_time)}
              </span>
              {line.text}
            </button>
          );
        })}
    </div>
  );
}