import { Outlet } from "react-router";
import Sidebar from "./Sidebar";
import Terminal from "./Terminal";

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
          <div className="app-terminal">
            <Terminal onSessionExpired={onSessionExpired} />
          </div>
        </div>
      </div>
    </div>
  );
}
