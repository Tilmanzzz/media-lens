"use client";

import type { Chapter } from "@/lib/types";
import dynamic from "next/dynamic";
import { useState } from "react";
import PodcastPlayer from "@/components/ui/podcastplayer";

const EmotionChart = dynamic(() => import("@/components/ui/chart"));
const Chat = dynamic(() => import("@/components/ui/chat"));

interface PanelConfig {
  transcript: boolean;
  emotionChart: boolean;
  themen: boolean;
  faktencheck: boolean;
  chat: boolean;
}

const PANEL_LABELS: Record<keyof PanelConfig, string> = {
  transcript:   "Transkript",
  emotionChart: "Emotionsverlauf",
  themen:       "Themen",
  faktencheck:  "Faktencheck",
  chat:         "KI-Chat",
};

interface PodcastDetailClientProps {
  src: string;
  episodeId: string;
  chapters: Chapter[];
  emotionData: {
    segments: { start: number; end: number; dominant: string; score: number }[];
  };
}

export default function PodcastDetailClient({
  src,
  episodeId,
  chapters,
  emotionData,
}: PodcastDetailClientProps) {
  const [panels, setPanels] = useState<PanelConfig>({
    transcript:   true,
    emotionChart: true,
    themen:       true,
    faktencheck:  true,
    chat:         true,
  });

  const toggle = (key: keyof PanelConfig) => {
    setPanels((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  return (
    <div className="flex flex-row gap-6 w-full bg-background-raised mt-6 px-4 py-6">

      {/* Hauptinhalt */}
      <div className="flex-1 flex flex-col gap-6">
        <PodcastPlayer
          src={src}
          chapters={chapters}
          showTranscript={panels.transcript}
          showThemen={panels.themen}
          showFaktencheck={panels.faktencheck}
        >
          {panels.emotionChart && <EmotionChart data={emotionData} />}
        </PodcastPlayer>

        {panels.chat && <Chat episodeId={episodeId} />}
      </div>

      {/* Konfigurations-Panel */}
      <div className="w-64 shrink-0">
        <p className="text-sm font-medium text-foreground mb-4">Ansicht anpassen</p>
        <div className="flex flex-col gap-2">
          {(Object.keys(panels) as (keyof PanelConfig)[]).map((key) => (
            <button
              key={key}
              onClick={() => toggle(key)}
              className={`flex items-center justify-between w-full px-3 py-2.5 rounded-lg border text-sm transition-all cursor-pointer
                ${panels[key]
                  ? "bg-primary-muted border-primary text-foreground"
                  : "bg-background-card border-border text-foreground-subtle hover:bg-background-raised"
                }`}
            >
              <span>{PANEL_LABELS[key]}</span>
              <span className={`w-4 h-4 rounded-full border-2 transition-colors ${panels[key] ? "bg-primary border-primary" : "border-foreground-subtle"}`} />
            </button>
          ))}
        </div>
      </div>

    </div>
  );
}