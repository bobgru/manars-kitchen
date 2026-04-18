import { useState, useRef, useEffect, useCallback, type KeyboardEvent, type ClipboardEvent } from "react";
import { executeCommand } from "../api/execute";
import { AuthError } from "../api/client";
import { useAllEvents } from "../hooks/useSSE";

interface TerminalProps {
  onSessionExpired: () => void;
}

interface OutputLine {
  type: "command" | "output" | "error" | "echo";
  text: string;
}

export default function Terminal({ onSessionExpired }: TerminalProps) {
  const [lines, setLines] = useState<OutputLine[]>([]);
  const [input, setInput] = useState("");
  const [history, setHistory] = useState<string[]>([]);
  const [historyIndex, setHistoryIndex] = useState(-1);
  const [loading, setLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Auto-scroll to bottom when new output is added or loading changes
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [lines, loading]);

  // Refocus input after loading completes
  useEffect(() => {
    if (!loading) {
      inputRef.current?.focus();
    }
  }, [loading]);

  // Focus input on mount
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const clientIdRef = useRef(crypto.randomUUID());

  useAllEvents(useCallback((event) => {
    if (event.clientId === clientIdRef.current) return;
    setLines((prev) => [...prev, { type: "echo", text: `[echo] ${event.command}` }]);
  }, []));

  async function runCommand(cmd: string) {
    const trimmed = cmd.trim();
    if (!trimmed) return;

    setLines((prev) => [...prev, { type: "command", text: `> ${trimmed}` }]);

    setLoading(true);
    try {
      const output = await executeCommand(trimmed, clientIdRef.current);
      if (output) {
        setLines((prev) => [...prev, { type: "output", text: output }]);
      }
    } catch (err) {
      if (err instanceof AuthError) {
        onSessionExpired();
        return;
      }
      const message = err instanceof Error ? err.message : String(err);
      setLines((prev) => [...prev, { type: "error", text: message }]);
    } finally {
      setLoading(false);
    }
  }

  async function handleSubmit() {
    const trimmed = input.trim();
    if (!trimmed || loading) return;

    setHistory((prev) => [...prev, trimmed]);
    setHistoryIndex(-1);
    setInput("");
    await runCommand(trimmed);
  }

  function handleKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") {
      e.preventDefault();
      handleSubmit();
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      if (history.length === 0) return;
      const newIndex =
        historyIndex === -1 ? history.length - 1 : Math.max(0, historyIndex - 1);
      setHistoryIndex(newIndex);
      setInput(history[newIndex]);
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      if (historyIndex === -1) return;
      const newIndex = historyIndex + 1;
      if (newIndex >= history.length) {
        setHistoryIndex(-1);
        setInput("");
      } else {
        setHistoryIndex(newIndex);
        setInput(history[newIndex]);
      }
    }
  }

  async function handlePaste(e: ClipboardEvent<HTMLInputElement>) {
    const text = e.clipboardData.getData("text");
    if (!text.includes("\n")) return; // Let default paste handle single-line

    e.preventDefault();
    const pasteLines = text.split("\n").filter((l) => l.trim());
    for (const line of pasteLines) {
      await runCommand(line);
    }
  }

  return (
    <div
      className="terminal"
      ref={scrollRef}
      onClick={() => inputRef.current?.focus()}
    >
      <div className="terminal-content">
        {lines.map((line, i) => (
          <pre
            key={i}
            className={`terminal-line terminal-${line.type}`}
          >
            {line.text}
          </pre>
        ))}
        <div className="terminal-input-row">
          <span className="terminal-prompt">&gt;&nbsp;</span>
          <input
            ref={inputRef}
            className="terminal-input"
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            onPaste={handlePaste}
            disabled={loading}
            spellCheck={false}
            autoComplete="off"
          />
          {loading && <span className="terminal-spinner" />}
        </div>
      </div>
    </div>
  );
}
