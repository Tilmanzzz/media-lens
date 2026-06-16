// GET /api/episodes?q=...&cursor=...&limit=20
// Entspricht: GET /v1/episodes aus api-contracts.yml

import { NextRequest, NextResponse } from "next/server";

const MOCK_EPISODES = [
  {
    id: "30000000-0000-0000-0000-000000000001",
    title: "KI & die Grenzen des Verstehens",
    podcast_name: "MediaLens Podcast",
    duration_seconds: 3738,
    published_at: "2024-03-15",
    cover_url: "/dummy-pic01.jpg",
  },
  {
    id: "30000000-0000-0000-0000-000000000002",
    title: 'The "97% consensus" claim: true, misleading, or both?',
    podcast_name: "Climate Decoded",
    duration_seconds: 2640,
    published_at: "2024-05-20",
    cover_url: "/dummy-pic03.jpg",
  },
  {
    id: "30000000-0000-0000-0000-000000000003",
    title: "Emotionen im Podcast analysieren",
    podcast_name: "Data Talks",
    duration_seconds: 1500,
    published_at: "2025-10-12",
    cover_url: "/dummy-pic03.jpg",
  },
];

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const q = searchParams.get("q")?.toLowerCase() ?? "";
  const limit = Math.min(Number(searchParams.get("limit") ?? 20), 100);
  const cursor = searchParams.get("cursor");

  let filtered = MOCK_EPISODES.filter(
    (e) =>
      e.title.toLowerCase().includes(q) ||
      e.podcast_name.toLowerCase().includes(q)
  );

  // Cursor-basierte Pagination
  const cursorIndex = cursor ? filtered.findIndex((e) => e.id === cursor) + 1 : 0;
  const page = filtered.slice(cursorIndex, cursorIndex + limit);
  const next_cursor = page.length === limit ? page[page.length - 1].id : null;

  return NextResponse.json({
    items: page,
    next_cursor,
    total: filtered.length,
  });
}
