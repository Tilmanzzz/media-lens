// POST /api/chat/conversations/[conversationId]/messages
// Entspricht: POST /v1/chat/conversations/{conversationId}/messages
// Antwortet als NDJSON-Stream (type: token | done | error)

import { NextRequest } from "next/server";

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ conversationId: string }> }
) {
  const { conversationId } = await params;
  const body = await req.json();
  const { text } = body;

  if (!text) {
    return new Response(
      JSON.stringify({ type: "error", message: "text fehlt." }) + "\n",
      { status: 400, headers: { "Content-Type": "application/x-ndjson" } }
    );
  }

  // Mock-Antwort als NDJSON-Stream
  const mockAnswer = `Das ist eine gemockte Antwort für Conversation ${conversationId}. Du hast gefragt: "${text}". Im echten Backend wird hier das RAG-System antworten.`;
  const tokens = mockAnswer.split(" ");

  const stream = new ReadableStream({
    async start(controller) {
      for (const token of tokens) {
        const chunk = JSON.stringify({ type: "token", delta: token + " " }) + "\n";
        controller.enqueue(new TextEncoder().encode(chunk));
        // Simuliertes Streaming-Delay
        await new Promise((r) => setTimeout(r, 40));
      }
      controller.enqueue(
        new TextEncoder().encode(JSON.stringify({ type: "done" }) + "\n")
      );
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "application/x-ndjson",
      "Transfer-Encoding": "chunked",
      "Cache-Control": "no-cache",
    },
  });
}