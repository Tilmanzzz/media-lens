"use client";
 
import { useState, useRef, useEffect } from "react";
 
interface Message {
  role: "user" | "assistant";
  content: string;
}
 
interface ChatProps {
  episodeId: string;
  placeholder?: string;
}
 
export default function Chat({
  episodeId,
  placeholder = "Frag etwas zu dieser Episode...",
}: ChatProps) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
 
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isLoading]);
 
  const handleSubmit = async () => {
    const query = input.trim();
    if (!query || isLoading) return;
 
    const userMessage: Message = { role: "user", content: query };
    setMessages((prev) => [...prev, userMessage]);
    setInput("");
    setIsLoading(true);
 
    try {
      const res = await fetch("/api/rag", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query, episodeId }),
      });
 
      const data = await res.json();
      const assistantMessage: Message = {
        role: "assistant",
        content: data.answer ?? "Keine Antwort erhalten.",
      };
      setMessages((prev) => [...prev, assistantMessage]);
    } catch {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: "Fehler beim Abrufen der Antwort." },
      ]);
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
 
  // Textarea auto-resize
  const handleInput = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(e.target.value);
    const el = e.target;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  };
 
  return (
    <div className="flex flex-col  bg-background-card border border-border rounded-xl overflow-hidden">
 
      {/* Nachrichtenverlauf */}
      <div className="flex-1  px-4 py-4 flex flex-col gap-3">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center gap-2 text-center py-8">
            <p className="text-sm text-foreground-subtle">
              Stelle Fragen zum Inhalt dieser Episode.
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
            </div>
          </div>
        ))}
 
        {isLoading && (
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
          placeholder={placeholder}
          rows={1}
          className="flex-1 resize-none bg-background-raised border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus:outline-none focus:border-primary transition-colors max-h-32 overflow-y-auto"
        />
        <button
          onClick={handleSubmit}
          disabled={!input.trim() || isLoading}
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
