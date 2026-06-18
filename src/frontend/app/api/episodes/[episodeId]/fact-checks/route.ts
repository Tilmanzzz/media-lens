// GET /api/episodes/[episodeId]/fact-checks
// Entspricht: GET /v1/episodes/{episodeId}/fact-checks aus api-contracts.yml

import { NextRequest, NextResponse } from "next/server";

const MOCK_FACT_CHECKS: Record<string, object[]> = {
  "30000000-0000-0000-0000-000000000003": [
    {
      id: "fc-00000001",
      start_time: 0,
      claim: "97% of scientists agree on climate change.",
      verdict: "MOSTLY_TRUE",
      explanation:
        "Die 97% stammen aus einer Metaanalyse von Cook et al. (2013), die über 12.000 Abstracts auswertete. Der Konsens ist real, bezieht sich aber spezifisch auf menschengemachte Erwärmung.",
      sources: [
        "https://iopscience.iop.org/article/10.1088/1748-9326/8/2/024024",
      ],
    },
    {
      id: "fc-00000002",
      start_time: 28,
      claim: "Two-thirds of papers were neutral on attribution.",
      verdict: "TRUE",
      explanation:
        "Korrekt – Cook et al. selbst weisen darauf hin, dass 66% der analysierten Abstracts keine explizite Position zur Attribution einnahmen.",
      sources: [
        "https://iopscience.iop.org/article/10.1088/1748-9326/8/2/024024",
      ],
    },
  ],
};

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ episodeId: string }> }
) {
  const { episodeId } = await params;
  const claims = MOCK_FACT_CHECKS[episodeId];

  if (!claims) {
    return NextResponse.json(
      { error: "episode_not_found", message: "Episode nicht gefunden.", status: 404 },
      { status: 404 }
    );
  }

  return NextResponse.json({ episode_id: episodeId, claims });
}