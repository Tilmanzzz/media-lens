"use client";

import { useState, useRef, MutableRefObject, ReactNode } from "react";
import AudioPlayer from "@/components/ui/audio";
import { TopicCard } from "@/components/ui/cardThemen";

interface Topic {
  name: string;
  summary: string;
  start: number;
  end: number;
}

interface PodcastPlayerProps {
  src: string;
  topics: Topic[];
  children?: ReactNode;    // Slot für EmotionChart
  factChecks?: ReactNode;  // Slot für Faktencheck
}

export default function PodcastPlayer({ src, topics, children, factChecks }: PodcastPlayerProps) {
  const [currentTime, setCurrentTime] = useState<number>(0);
  const seekRef = useRef<((time: number) => void) | null>(null);

  const activeTopic = topics.findIndex(
    (t) => currentTime >= t.start && currentTime < t.end
  );

  return (
    <div className="flex flex-col gap-6 w-full">
      {/* 1. AudioPlayer */}
      <AudioPlayer
        src={src}
        onTimeUpdate={setCurrentTime}
        seekRef={seekRef as MutableRefObject<((time: number) => void) | null>}
      />

      {/* 2. EmotionChart */}
      {children}

      {/* 3. Themen + Faktencheck nebeneinander */}
      <div className="flex flex-row gap-6 items-start">
        <div className="flex-1">
          <p className="text-sm text-foreground-muted mb-3">Themen</p>
          <div className="flex flex-col gap-3">
            {topics.map((topic, index) => (
              <TopicCard
                key={index}
                topic={topic}
                isActive={activeTopic === index}
                onSelect={(start) => seekRef.current?.(start)}
              />
            ))}
          </div>
        </div>

        {factChecks && (
          <div className="flex-1">
            <p className="text-sm text-foreground-muted mb-3">Faktencheck</p>
            <div className="flex flex-col gap-3">
              {factChecks}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}