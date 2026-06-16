// GET /api/episodes/[episodeId]/transcript
// Entspricht: GET /v1/episodes/{episodeId}/transcript aus api-contracts.yml

import { NextRequest, NextResponse } from "next/server";

const MOCK_TRANSCRIPT: Record<string, object[]> = {
  "30000000-0000-0000-0000-000000000003": [
    {
      id: "tl-00000001",
      start_time: 0,
      text: "Sarah: Let's start with the most cited number in climate discourse: 97% of scientists agree on climate change.",
      has_fact_flag: true,
    },
    {
      id: "tl-00000002",
      start_time: 12,
      text: "James: It's real, but it needs context. The figure comes from a 2013 meta-analysis by Cook et al.",
      has_fact_flag: false,
    },
    {
      id: "tl-00000003",
      start_time: 28,
      text: "Sarah: But critics say most papers didn't express a position at all.",
      has_fact_flag: false,
    },
    {
      id: "tl-00000004",
      start_time: 40,
      text: "James: That's true – about two-thirds were neutral on attribution. But that doesn't undermine the finding.",
      has_fact_flag: false,
    },
  ],
};

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ episodeId: string }> }
) {
  const { episodeId } = await params;
  const lines = MOCK_TRANSCRIPT[episodeId];

  if (!lines) {
    return NextResponse.json(
      { error: "episode_not_found", message: "Episode nicht gefunden.", status: 404 },
      { status: 404 }
    );
  }

  return NextResponse.json({ episode_id: episodeId, lines });
}