// GET /api/episodes/[episodeId]
// Entspricht: GET /v1/episodes/{episodeId} aus api-contracts.yml

import { NextRequest, NextResponse } from "next/server";

const MOCK_EPISODES: Record<string, object> = {
  "30000000-0000-0000-0000-000000000003": {
    id: "30000000-0000-0000-0000-000000000003",
    title: 'The "97% consensus" claim: true, misleading, or both?',
    podcast_name: "Climate Decoded",
    duration_seconds: 2640,
    published_at: "2024-05-20",
    cover_url: "/dummy-pic03.jpg",
  },
};

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ episodeId: string }> }
) {
  const { episodeId } = await params;
  const episode = MOCK_EPISODES[episodeId];

  if (!episode) {
    return NextResponse.json(
      { error: "episode_not_found", message: "Episode mit dieser ID existiert nicht.", status: 404 },
      { status: 404 }
    );
  }

  return NextResponse.json({ episode });
}
