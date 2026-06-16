// POST /api/chat/conversations
// Entspricht: POST /v1/chat/conversations aus api-contracts.yml

import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "crypto";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { episode_id } = body;

  if (!episode_id) {
    return NextResponse.json(
      { error: "bad_request", message: "episode_id fehlt.", status: 400 },
      { status: 400 }
    );
  }

  // Im echten Backend: Session in DB anlegen
  const conversation_id = randomUUID();
  return NextResponse.json({ conversation_id }, { status: 201 });
}