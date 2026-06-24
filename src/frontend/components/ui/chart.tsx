"use client";

import { useEffect, useRef, useState } from "react";

export interface EmotionSegment {
  start: number;   // Sekunden
  end: number;     // Sekunden
  dominant: string;
  score: number;   // 0–1
}

export interface EmotionData {
  segments: EmotionSegment[];
}

interface EmotionChartProps {
  data: EmotionData;
}

const EMOTION_COLORS: Record<string, string> = {
  angry:   "#E24B4A",
  happy:   "#9FE1CB",
  neutral: "#888780",
  sad:     "#B4B2A9",
};

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
}

function getColor(emotion: string): string {
  return EMOTION_COLORS[emotion] ?? "#888780";
}

export default function EmotionChart({ data }: EmotionChartProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [tooltip, setTooltip] = useState<{
    x: number;
    y: number;
    segment: EmotionSegment;
  } | null>(null);

  const segments = data.segments;
  const totalDuration = segments.at(-1)?.end ?? 1;

  // Alle einzigartigen Emotionen für die Legende
  const uniqueEmotions = Array.from(
    new Set(segments.map((s) => s.dominant))
  );

  // Datenpunkte: Mitte jedes Segments
  const points = segments.map((seg) => ({
    time: (seg.start + seg.end) / 2,
    value: Math.round(seg.score * 100),
    segment: seg,
  }));

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;

    const ctx = canvas.getContext("2d")!;
    ctx.scale(dpr, dpr);

    const W = rect.width;
    const H = rect.height;
    const PAD_L = 12;
    const PAD_R = 12;
    const PAD_T = 16;
    const PAD_B = 28;

    const toX = (t: number) => PAD_L + (t / totalDuration) * (W - PAD_L - PAD_R);
    const toY = (v: number) => PAD_T + ((100 - v) / 100) * (H - PAD_T - PAD_B);

    // Hintergrundlinien
    ctx.strokeStyle = "rgba(255,255,255,0.08)";
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= 4; i++) {
      const y = PAD_T + (i / 4) * (H - PAD_T - PAD_B);
      ctx.beginPath();
      ctx.moveTo(PAD_L, y);
      ctx.lineTo(W - PAD_R, y);
      ctx.stroke();
    }

    // Linie zwischen Punkten
    ctx.beginPath();
    ctx.strokeStyle = "rgba(255,255,255,0.85)";
    ctx.lineWidth = 2;
    ctx.lineJoin = "round";
    points.forEach((pt, i) => {
      const x = toX(pt.time);
      const y = toY(pt.value);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    // Zeitlabels auf X-Achse (nur bei bestimmten Segmenten)
    ctx.fillStyle = "rgba(255,255,255,0.4)";
    ctx.font = "11px sans-serif";
    ctx.textAlign = "center";
    points.forEach((pt, i) => {
      if (i % 2 === 1) {
        ctx.fillText(formatTime(pt.time), toX(pt.time), H - 6);
      }
    });

    // Punkte zeichnen
    points.forEach((pt) => {
      const x = toX(pt.time);
      const y = toY(pt.value);
      const color = getColor(pt.segment.dominant);

      ctx.beginPath();
      ctx.arc(x, y, 7, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();

      // weißer Ring
      ctx.beginPath();
      ctx.arc(x, y, 7, 0, Math.PI * 2);
      ctx.strokeStyle = "rgba(255,255,255,0.3)";
      ctx.lineWidth = 1.5;
      ctx.stroke();
    });
  }, [data, points, totalDuration]);

  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    const wrapper = wrapperRef.current;
    if (!canvas || !wrapper) return;

    const rect = canvas.getBoundingClientRect();
    const W = rect.width;
    const PAD_L = 12;
    const PAD_R = 12;

    const mouseX = e.clientX - rect.left;

    const toX = (t: number) => PAD_L + (t / totalDuration) * (W - PAD_L - PAD_R);

    // Nächsten Punkt finden
    let closest = points[0];
    let minDist = Infinity;
    points.forEach((pt) => {
      const dist = Math.abs(toX(pt.time) - mouseX);
      if (dist < minDist) {
        minDist = dist;
        closest = pt;
      }
    });

    if (minDist < 30) {
      const wrapRect = wrapper.getBoundingClientRect();
      setTooltip({
        x: e.clientX - wrapRect.left,
        y: e.clientY - wrapRect.top,
        segment: closest.segment,
      });
    } else {
      setTooltip(null);
    }
  };

  return (
    <div className="w-full rounded-xl p-5" style={{ background: "#1a2035" }}>
      {/* Titel */}
      <p className="text-sm font-medium mb-4">
        Emotion Verlauf
      </p>

      <div className="flex gap-4">
        {/* Legende links */}
        <div className="flex flex-col gap-2 justify-around shrink-0">
          {uniqueEmotions.map((em) => (
            <div key={em} className="flex items-center gap-2">
              <div
                className="rounded-sm shrink-0"
                style={{ width: 22, height: 14, background: getColor(em) }}
              />
              <span className="text-xs" style={{ color: "rgba(255,255,255,0.45)", whiteSpace: "nowrap" }}>
                {em}
              </span>
            </div>
          ))}
        </div>

        {/* Chart */}
        <div ref={wrapperRef} className="flex-1 relative" style={{ height: 200 }}>
          <canvas
            ref={canvasRef}
            onMouseMove={handleMouseMove}
            onMouseLeave={() => setTooltip(null)}
            className="w-full h-full cursor-crosshair"
            role="img"
            aria-label="Emotionsverlauf des Podcasts"
          />

          {/* Tooltip */}
          {tooltip && (
            <div
              className="absolute pointer-events-none rounded-lg px-3 py-2 text-xs"
              style={{
                left: tooltip.x - 60,
                top: tooltip.y - 76,
                background: "rgba(20,28,50,0.95)",
                border: "0.5px solid rgba(255,255,255,0.15)",
                color: "rgba(255,255,255,0.9)",
                minWidth: 120,
              }}
            >
              <div className="flex items-center gap-2 mb-1">
                <div
                  className="rounded-sm"
                  style={{ width: 10, height: 10, background: getColor(tooltip.segment.dominant), flexShrink: 0 }}
                />
                <span className="font-medium">{tooltip.segment.dominant}</span>
              </div>
              <div style={{ color: "rgba(255,255,255,0.5)" }}>
                {formatTime(tooltip.segment.start)} – {formatTime(tooltip.segment.end)}
              </div>
              <div style={{ color: "rgba(255,255,255,0.5)" }}>
                Score: {Math.round(tooltip.segment.score * 100)}%
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Farbbalken unten */}
      <div className="flex gap-1.5 mt-4" style={{ marginLeft: "calc(22px + 1rem + 8px)" }}>
        {segments.map((seg, i) => (
          <div
            key={i}
            className="rounded flex-1"
            style={{ height: 24, background: getColor(seg.dominant), minWidth: 20, opacity: 0.85 }}
            title={seg.dominant}
          />
        ))}
      </div>
    </div>
  );
}


