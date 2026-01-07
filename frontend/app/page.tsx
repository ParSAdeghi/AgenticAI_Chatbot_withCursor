"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

type Role = "user" | "assistant";
type ChatMsg = { role: Role; content: string; ts: number };
type Thread = { location: string; messages: ChatMsg[]; updatedAt: number };

const STORAGE_KEY = "canada_tourist_threads_v1";

function loadThreads(): Thread[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Thread[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveThreads(threads: Thread[]) {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(threads));
}

function backendUrl() {
  return process.env.NEXT_PUBLIC_BACKEND_URL || "http://localhost:8000";
}

async function extractLocation(message: string, history: { role: Role; content: string }[]): Promise<string> {
  const r = await fetch(`${backendUrl()}/extract-location`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, history })
  });
  if (!r.ok) return "General";
  const data = (await r.json()) as { location?: string };
  return (data.location || "General").trim() || "General";
}

async function sendChat(message: string, history: { role: Role; content: string }[]) {
  const r = await fetch(`${backendUrl()}/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, history })
  });
  if (!r.ok) {
    const txt = await r.text().catch(() => "");
    throw new Error(`Backend error: ${r.status} ${txt}`);
  }
  return (await r.json()) as { reply: string };
}

export default function HomePage() {
  const [threads, setThreads] = useState<Thread[]>([]);
  const [activeLocation, setActiveLocation] = useState<string>("General");
  const [input, setInput] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const activeThread = useMemo(() => {
    return threads.find((t) => t.location === activeLocation) || null;
  }, [threads, activeLocation]);

  const bottomRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    setThreads(loadThreads());
  }, []);
  useEffect(() => {
    if (typeof window !== "undefined") saveThreads(threads);
  }, [threads]);
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [activeLocation, activeThread?.messages.length]);

  function upsertThread(location: string, updater: (t: Thread) => Thread) {
    setThreads((prev) => {
      const now = Date.now();
      const idx = prev.findIndex((t) => t.location === location);
      if (idx === -1) {
        const created: Thread = { location, messages: [], updatedAt: now };
        const updated = updater(created);
        return [updated, ...prev].sort((a, b) => b.updatedAt - a.updatedAt);
      }
      const next = [...prev];
      next[idx] = updater(next[idx]);
      next[idx] = { ...next[idx], updatedAt: now };
      return next.sort((a, b) => b.updatedAt - a.updatedAt);
    });
  }

  async function onSend() {
    const msg = input.trim();
    if (!msg || isSending) return;
    setError(null);
    setIsSending(true);

    try {
      // Build potential history for context (from current active thread if exists)
      // Note: We use the currently active thread's messages as context for extraction,
      // even though the user might be switching topics. This helps resolve "it" references.
      const currentHistory = activeThread ? activeThread.messages.map((m) => ({ role: m.role, content: m.content })) : [];
      
      const location = await extractLocation(msg, currentHistory);
      setActiveLocation(location);

      const prior =
        threads.find((t) => t.location === location)?.messages || ([] as ChatMsg[]);

      const userMsg: ChatMsg = { role: "user", content: msg, ts: Date.now() };
      const history = [...prior, userMsg].map((m) => ({ role: m.role, content: m.content }));

      upsertThread(location, (t) => ({ ...t, messages: [...t.messages, userMsg] }));
      const res = await sendChat(msg, history);

      const assistantMsg: ChatMsg = {
        role: "assistant",
        content: res.reply,
        ts: Date.now()
      };
      upsertThread(location, (t) => ({ ...t, messages: [...t.messages, assistantMsg] }));
      setInput("");
    } catch (e: any) {
      setError(e?.message || "Failed to send message.");
    } finally {
      setIsSending(false);
    }
  }

  return (
    <div className="h-screen w-full bg-black text-zinc-100">
      <div className="mx-auto flex h-full max-w-6xl gap-3 p-3">
        <aside className="w-72 shrink-0 rounded-xl border border-zinc-800 bg-zinc-950 p-3">
          <div className="mb-3">
            <div className="text-sm font-semibold text-zinc-100">Chat history</div>
            <div className="text-xs text-zinc-400">Grouped by location</div>
          </div>

          <div className="space-y-1 overflow-auto">
            {threads.length === 0 ? (
              <div className="text-sm text-zinc-500">No history yet.</div>
            ) : (
              threads.map((t) => (
                <button
                  key={t.location}
                  onClick={() => setActiveLocation(t.location)}
                  className={[
                    "w-full rounded-lg px-3 py-2 text-left text-sm",
                    t.location === activeLocation
                      ? "bg-zinc-800 text-zinc-50"
                      : "bg-transparent text-zinc-200 hover:bg-zinc-900"
                  ].join(" ")}
                >
                  <div className="font-medium">{t.location}</div>
                  <div className="truncate text-xs text-zinc-500">
                    {t.messages.slice(-1)[0]?.content || ""}
                  </div>
                </button>
              ))
            )}
          </div>
        </aside>

        <main className="flex min-w-0 flex-1 flex-col rounded-xl border border-zinc-800 bg-zinc-950">
          <div className="border-b border-zinc-800 px-4 py-3">
            <div className="text-sm font-semibold">Canada Tourist Agent</div>
            <div className="text-xs text-zinc-400">
              Active thread: <span className="text-zinc-200">{activeLocation}</span>
            </div>
          </div>

          <div className="flex-1 overflow-auto px-4 py-4">
            {(activeThread?.messages || []).length === 0 ? (
              <div className="text-sm text-zinc-500">
                Ask about a Canadian location (e.g., Toronto, Alberta, Vancouver).
              </div>
            ) : (
              <div className="space-y-3">
                {(activeThread?.messages || []).map((m, idx) => (
                  <div
                    key={idx}
                    className={[
                      "max-w-[85%] rounded-2xl px-4 py-3 text-sm leading-relaxed",
                      m.role === "user"
                        ? "ml-auto bg-zinc-800 text-zinc-50"
                        : "mr-auto bg-zinc-900 text-zinc-100"
                    ].join(" ")}
                  >
                    {m.role === "assistant" ? (
                      <div className="prose prose-invert prose-sm max-w-none prose-p:my-2 prose-ul:my-2 prose-li:my-1">
                        <ReactMarkdown remarkPlugins={[remarkGfm]}>
                          {m.content}
                        </ReactMarkdown>
                      </div>
                    ) : (
                      <div className="whitespace-pre-wrap">{m.content}</div>
                    )}
                  </div>
                ))}
              </div>
            )}
            <div ref={bottomRef} />
          </div>

          <div className="border-t border-zinc-800 p-3">
            {error ? (
              <div className="mb-2 rounded-lg border border-red-900 bg-red-950 px-3 py-2 text-xs text-red-200">
                {error}
              </div>
            ) : null}

            <div className="flex gap-2">
              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) onSend();
                }}
                placeholder="Ask about attractions in Canada…"
                className="flex-1 rounded-xl border border-zinc-800 bg-black px-4 py-3 text-sm text-zinc-100 placeholder:text-zinc-600 outline-none focus:border-zinc-600"
                disabled={isSending}
              />
              <button
                onClick={onSend}
                disabled={isSending || !input.trim()}
                className="rounded-xl bg-zinc-200 px-4 py-3 text-sm font-semibold text-black disabled:opacity-40"
              >
                {isSending ? "Sending…" : "Send"}
              </button>
            </div>
            <div className="mt-2 text-xs text-zinc-500">
              Note: Responses avoid promoting businesses and won’t name hotels/brands.
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

