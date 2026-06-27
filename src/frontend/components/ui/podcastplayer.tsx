"use client";

import { useState, useRef, MutableRefObject, ReactNode } from "react";
import AudioPlayer from "@/components/ui/audio";
import type { Chapter } from "@/lib/types";

interface PodcastPlayerProps {
  src: string;
  chapters: Chapter[];
  children?: ReactNode;
  onTimeUpdate?: (time: number) => void;
  onFilterToggle?: (index: number) => void;
  filteredChapterIndex?: number | null;
  seekRef?: MutableRefObject<((time: number) => void) | null>;
}

export default function PodcastPlayer({
  src,
  children,
  onTimeUpdate,
  seekRef: externalSeekRef,
}: PodcastPlayerProps) {
  const internalSeekRef = useRef<((time: number) => void) | null>(null);
  const seekRef = externalSeekRef ?? internalSeekRef;

  return (
    <div className="flex flex-col gap-6 w-full">
      {/* AudioPlayer */}
      <AudioPlayer
        src={src}
        onTimeUpdate={onTimeUpdate}
        seekRef={seekRef as MutableRefObject<((time: number) => void) | null>}
      />

      {/* Slot: EmotionChart */}
      {children}
    </div>
  );
}