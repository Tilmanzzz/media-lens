"use client";

import { useState, useRef, useEffect } from "react";

interface Message {
  role: "user" | "assistant";
  content: string;
  streaming?: boolean;
}

interface RagChatProps {
  episodeId: string;
  placeholder?: string;
}

export default function RagChat({
  episodeId,
  placeholder = "Frag etwas zu dieser Episode...",
}: RagChatProps) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Schritt 1: Chat-Session beim Laden der Komponente starten
  useEffect(() => {
    async function startConversation() {
      try {
        const res = await fetch("/api/chat/conversations", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ episode_id: episodeId }),
        });
        const data = await res.json();
        setConversationId(data.conversation_id);
      } catch {
        console.error("Konnte Chat-Session nicht starten.");
      }
    }
    startConversation();
  }, [episodeId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isLoading]);

  const handleSubmit = async () => {
    const query = input.trim();
    if (!query || isLoading || !conversationId) return;

    setMessages((prev) => [...prev, { role: "user", content: query }]);
    setInput("");
    setIsLoading(true);

    // Leere Assistenten-Nachricht anlegen die wir Stück für Stück befüllen
    setMessages((prev) => [
      ...prev,
      { role: "assistant", content: "", streaming: true },
    ]);

    try {
      // Schritt 2: Nachricht senden und Stream lesen
      const res = await fetch(
        `/api/chat/conversations/${conversationId}/messages`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: query }),
        }
      );

      if (!res.body) throw new Error("Kein Stream erhalten.");

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      // Schritt 3: Stream Zeile für Zeile lesen
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? ""; // letzte unvollständige Zeile im Buffer behalten

        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const chunk = JSON.parse(line);

            if (chunk.type === "token") {
              // Token an die letzte Assistenten-Nachricht anhängen
              setMessages((prev) => {
                const updated = [...prev];
                const last = updated[updated.length - 1];
                if (last.role === "assistant") {
                  updated[updated.length - 1] = {
                    ...last,
                    content: last.content + chunk.delta,
                  };
                }
                return updated;
              });
            } else if (chunk.type === "done") {
              // Stream fertig – streaming-Flag entfernen
              setMessages((prev) => {
                const updated = [...prev];
                const last = updated[updated.length - 1];
                if (last.role === "assistant") {
                  updated[updated.length - 1] = { ...last, streaming: false };
                }
                return updated;
              });
            } else if (chunk.type === "error") {
              setMessages((prev) => {
                const updated = [...prev];
                updated[updated.length - 1] = {
                  role: "assistant",
                  content: `Fehler: ${chunk.message}`,
                  streaming: false,
                };
                return updated;
              });
            }
          } catch {
            // ungültige JSON-Zeile überspringen
          }
        }
      }
    } catch {
      setMessages((prev) => {
        const updated = [...prev];
        updated[updated.length - 1] = {
          role: "assistant",
          content: "Fehler beim Abrufen der Antwort.",
          streaming: false,
        };
        return updated;
      });
    } finally {
      setIsLoading(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  };

  const handleInput = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(e.target.value);
    const el = e.target;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  };

  const canSend = input.trim() && !isLoading && conversationId;

  return (
    <div className="flex flex-col h-full min-h-64 bg-background-card border border-border rounded-xl overflow-hidden">

      {/* Nachrichtenverlauf */}
      <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-3">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full gap-2 text-center py-8">
            <p className="text-sm text-foreground-subtle">
              {conversationId
                ? "Stelle Fragen zum Inhalt dieser Episode."
                : "Chat wird gestartet..."}
            </p>
          </div>
        )}

        {messages.map((msg, index) => (
          <div
            key={index}
            className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}
          >
            <div
              className={`max-w-[80%] rounded-xl px-4 py-2.5 text-sm leading-relaxed
                ${msg.role === "user"
                  ? "bg-primary text-foreground rounded-br-sm"
                  : "bg-background-raised text-foreground border border-border rounded-bl-sm"
                }`}
            >
              {msg.content}
              {/* Blinkender Cursor während Stream läuft */}
              {msg.streaming && (
                <span className="inline-block w-0.5 h-4 bg-foreground ml-0.5 animate-pulse" />
              )}
            </div>
          </div>
        ))}

        {/* Lade-Dots nur bevor erster Token kommt */}
        {isLoading && messages[messages.length - 1]?.content === "" && (
          <div className="flex justify-start">
            <div className="bg-background-raised border border-border rounded-xl rounded-bl-sm px-4 py-3 flex gap-1.5 items-center">
              <span className="w-1.5 h-1.5 rounded-full bg-foreground-subtle animate-bounce [animation-delay:0ms]" />
              <span className="w-1.5 h-1.5 rounded-full bg-foreground-subtle animate-bounce [animation-delay:150ms]" />
              <span className="w-1.5 h-1.5 rounded-full bg-foreground-subtle animate-bounce [animation-delay:300ms]" />
            </div>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Eingabefeld */}
      <div className="border-t border-border px-3 py-3 flex gap-2 items-end bg-background-card">
        <textarea
          ref={inputRef}
          value={input}
          onChange={handleInput}
          onKeyDown={handleKeyDown}
          placeholder={conversationId ? placeholder : "Chat wird gestartet..."}
          disabled={!conversationId}
          rows={1}
          className="flex-1 resize-none bg-background-raised border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus:outline-none focus:border-primary transition-colors max-h-32 overflow-y-auto disabled:opacity-50"
        />
        <button
          onClick={handleSubmit}
          disabled={!canSend}
          className="shrink-0 w-9 h-9 rounded-lg bg-primary hover:bg-primary-hover disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center transition-colors cursor-pointer"
          aria-label="Senden"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-foreground rotate-90">
            <line x1="12" y1="19" x2="12" y2="5" />
            <polyline points="5 12 12 5 19 12" />
          </svg>
        </button>
      </div>

    </div>
  );
}