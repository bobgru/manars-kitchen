import { useState, useRef, useEffect, useCallback, type KeyboardEvent, type ClipboardEvent } from "react";
import { executeCommand } from "../api/execute";
import { AuthError } from "../api/client";
import { useAllEvents } from "../hooks/useSSE";

interface TerminalProps {
  onSessionExpired: () => void;
  /** Collapsed to a one-line bar; the history and input stay mounted, just hidden. */
  collapsed: boolean;
  onToggle: () => void;
}

interface OutputLine {
  type: "command" | "output" | "error" | "echo";
  text: string;
}

export default function Terminal({ onSessionExpired, collapsed, onToggle }: TerminalProps) {
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

  // The last thing the terminal said, for the collapsed bar: the final non-empty
  // line of the last output, so a command can be fired, the panel collapsed, and
  // its answer still read.
  const lastLine = (() => {
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].type === "command") return `> ${lines[i].text}`;
      const text = lines[i].text.trim().split("\n").filter(Boolean).pop();
      if (text) return text;
    }
    return "";
  })();

  return (
    <div className={collapsed ? "terminal-panel terminal-panel-collapsed" : "terminal-panel"}>
      {/* The bar is the toggle: a real button with a word and a glyph, so the
          state is never carried by colour or by an icon alone. */}
      <div className="terminal-bar">
        <button
          type="button"
          className="terminal-toggle"
          aria-expanded={!collapsed}
          aria-controls="terminal-body"
          onClick={onToggle}
          title={collapsed ? "Show the terminal" : "Collapse the terminal to a bar"}
        >
          {collapsed ? "▸ Terminal" : "▾ Terminal"}
        </button>
        {collapsed && (
          <span className="terminal-last" title={lastLine || undefined}>
            {lastLine || "CLI commands run here; expand to type one."}
          </span>
        )}
      </div>
      {/* Hidden, not unmounted, so history, scroll position and focus survive. */}
      <div
        id="terminal-body"
        className="terminal"
        hidden={collapsed}
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
    </div>
  );
}
