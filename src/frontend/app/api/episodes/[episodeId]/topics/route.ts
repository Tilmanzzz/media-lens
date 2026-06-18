// GET /api/episodes/[episodeId]/topics
// Entspricht: GET /v1/episodes/{episodeId}/topics aus api-contracts.yml

import { NextRequest, NextResponse } from "next/server";

const MOCK_TOPICS: Record<string, object[]> = {
  "30000000-0000-0000-0000-000000000003": [
    {
      id: "40000000-0000-0000-0000-000000000001",
      topic: 'The "97% consensus" claim',
      start_time: 0,
      emotion: "neutral",
      summary: "A 2013 study found 97.1% of climate scientists agree on human-caused warming.",
    },
    {
      id: "40000000-0000-0000-0000-000000000002",
      topic: "What the critics say",
      start_time: 360,
      emotion: "negative",
      summary: "Critics argue the framing of the 97% is misleading without context.",
    },
  ],
};

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ episodeId: string }> }
) {
  const { episodeId } = await params;
  const topics = MOCK_TOPICS[episodeId];

  if (!topics) {
    return NextResponse.json(
      { error: "episode_not_found", message: "Episode nicht gefunden.", status: 404 },
      { status: 404 }
    );
  }

  return NextResponse.json({ episode_id: episodeId, topics });
}