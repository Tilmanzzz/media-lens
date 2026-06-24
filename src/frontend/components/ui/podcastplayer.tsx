"use client";

import { useState, useRef, MutableRefObject, ReactNode } from "react";
import AudioPlayer from "@/components/ui/audio";
import { TopicCard } from "@/components/ui/cardThemen";
import { FactCheckCard } from "./factcheck";
import Transcript from "./transcript";
import type { Chapter } from "@/lib/types";

interface PodcastPlayerProps {
  src: string;
  chapters: Chapter[];
  children?: ReactNode;
  showTranscript?: boolean;
  showThemen?: boolean;
  showFaktencheck?: boolean;
}

export default function PodcastPlayer({
  src,
  chapters,
  children,
  showTranscript = true,
  showThemen = true,
  showFaktencheck = true,
}: PodcastPlayerProps) {
  const [currentTime, setCurrentTime] = useState<number>(0);
  const [filteredChapterIndex, setFilteredChapterIndex] = useState<number | null>(null);
  const seekRef = useRef<((time: number) => void) | null>(null);

  const sorted = [...chapters].sort((a, b) => a.chapter_idx - b.chapter_idx);

  const activeChapterIndex = sorted.findIndex(
    (ch) => currentTime >= ch.start_time && currentTime < ch.end_time
  );

  const handleSeek = (time: number) => seekRef.current?.(time);

  const handleFilterToggle = (index: number) => {
    setFilteredChapterIndex((prev) => (prev === index ? null : index));
  };

  const allLines = sorted.flatMap((ch) => ch.transcript_lines ?? []);

  const visibleClaims =
    filteredChapterIndex !== null
      ? sorted[filteredChapterIndex]?.fact_checked_claims ?? []
      : sorted.flatMap((ch) => ch.fact_checked_claims ?? []);

  const filteredChapterName =
    filteredChapterIndex !== null ? sorted[filteredChapterIndex]?.title : null;

  return (
    <div className="flex flex-col gap-6 w-full">

      {/* 1. AudioPlayer */}
      <AudioPlayer
        src={src}
        onTimeUpdate={setCurrentTime}
        seekRef={seekRef as MutableRefObject<((time: number) => void) | null>}
      />

      {/* 2. Slot: EmotionChart o.ä. */}
      {children}

      {/* 3. Themen + Faktencheck nebeneinander */}
      {(showThemen || showFaktencheck) && (
        <div className="flex flex-col gap-6  lg:items-start">

          {showThemen && (
            <div className="w-100">
              <p className="text-lg text-foreground-subtle mb-3">Chapters</p>
              <div className="flex flex-col gap-3">
                {sorted.map((chapter, index) => (
                  <TopicCard
                    key={chapter.id}
                    topic={{
                      name: chapter.title ?? `Kapitel ${chapter.chapter_idx + 1}`,
                      summary: chapter.summary ?? "",
                      start: chapter.start_time,
                      end: chapter.end_time,
                    }}
                    isActive={activeChapterIndex === index}
                    isFiltered={filteredChapterIndex === index}
                    onSelect={handleSeek}
                    onFilterToggle={() => handleFilterToggle(index)}
                  />
                ))}
              </div>
            </div>
          )}

          {showFaktencheck && (
            <div className="lg:flex-[1]">
              <div className="rounded-2xl border border-border bg-background-card p-4">
                <div className="flex items-center justify-between mb-3">
                  <p className="text-lg text-foreground-subtle">
                    Factcheck
                    {filteredChapterName && (
                      <span className="ml-2 text-xs text-accent">· {filteredChapterName}</span>
                    )}
                  </p>
                  {filteredChapterIndex !== null && (
                    <button
                      onClick={() => setFilteredChapterIndex(null)}
                      className="text-xs text-foreground-subtle hover:text-foreground transition-colors cursor-pointer"
                    >
                      Show all x
                    </button>
                  )}
                </div>
                <div className="flex flex-col gap-3">
                  {visibleClaims.length > 0 ? (
                    visibleClaims.map((claim) => (
                      <FactCheckCard key={claim.id} claim={claim} />
                    ))
                  ) : (
                    <p className="text-xs text-foreground-subtle">
                     No Facts found.
                    </p>
                  )}
                </div>
              </div>
            </div>
          )}

        </div>
      )}

      {/* 4. Transkript – volle Breite unter Themen/Faktencheck */}
      {showTranscript && allLines.length > 0 && (
        <div>
          <p className="text-lg text-foreground-subtle mb-3">Transcript</p>
          <Transcript
            lines={allLines}
            currentTime={currentTime}
            onLineClick={handleSeek}
          />
        </div>
      )}

    </div>
  );
}