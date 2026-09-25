import { useEffect, useState } from "react";
import { Outlet } from "react-router";
import Sidebar from "./Sidebar";
import Terminal from "./Terminal";

/** Remembered per browser, so the choice holds across pages and visits. */
const COLLAPSED_KEY = "terminalCollapsed";

function readCollapsed(): boolean {
  try {
    return localStorage.getItem(COLLAPSED_KEY) === "1";
  } catch {
    return false;
  }
}

interface AppShellProps {
  username: string;
  onLogout: () => void;
  onSessionExpired: () => void;
}

export default function AppShell({
  username,
  onLogout,
  onSessionExpired,
}: AppShellProps) {
  // Open by default: the terminal is part of the pitch, the browser and the CLI
  // being one system. Collapsing it gives the page the whole height.
  const [terminalCollapsed, setTerminalCollapsed] = useState(readCollapsed);
  useEffect(() => {
    try {
      localStorage.setItem(COLLAPSED_KEY, terminalCollapsed ? "1" : "0");
    } catch {
      // Private mode or storage disabled: the choice just does not persist.
    }
  }, [terminalCollapsed]);

  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="app-title">Manar's Kitchen</span>
        <span className="app-user">
          {username}
          <button className="logout-btn" onClick={onLogout}>
            Log out
          </button>
        </span>
      </header>
      <div className="app-body">
        <Sidebar />
        <div className="app-content">
          <div className="app-page">
            <Outlet />
          </div>
          <div
            className={
              terminalCollapsed ? "app-terminal app-terminal-collapsed" : "app-terminal"
            }
          >
            <Terminal
              onSessionExpired={onSessionExpired}
              collapsed={terminalCollapsed}
              onToggle={() => setTerminalCollapsed((c) => !c)}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
