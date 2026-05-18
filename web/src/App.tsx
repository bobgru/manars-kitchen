import { useState, useCallback } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router";
import LoginPage from "./components/LoginPage";
import AppShell from "./components/AppShell";
import DashboardPage from "./components/DashboardPage";
import SkillsListPage from "./components/SkillsListPage";
import SkillDetailPage from "./components/SkillDetailPage";
import StationsListPage from "./components/StationsListPage";
import StationDetailPage from "./components/StationDetailPage";
import WorkersListPage from "./components/WorkersListPage";
import WorkerDetailPage from "./components/WorkerDetailPage";
import { SSEProvider } from "./hooks/useSSE";
import "./App.css";

function App() {
  const [authenticated, setAuthenticated] = useState(
    () => !!sessionStorage.getItem("token")
  );
  const [username, setUsername] = useState(
    () => sessionStorage.getItem("username") || ""
  );

  const handleLogin = useCallback(
    (_token: string, user: string, _role: string) => {
      setUsername(user);
      setAuthenticated(true);
    },
    []
  );

  const handleLogout = useCallback(async () => {
    try {
      const token = sessionStorage.getItem("token");
      await fetch("/api/logout", {
        method: "POST",
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
    } catch {
      // Ignore network errors on logout
    }
    sessionStorage.clear();
    setAuthenticated(false);
    setUsername("");
  }, []);

  const handleSessionExpired = useCallback(() => {
    sessionStorage.clear();
    setAuthenticated(false);
    setUsername("");
  }, []);

  if (!authenticated) {
    return <LoginPage onLogin={handleLogin} />;
  }

  return (
    <SSEProvider>
      <BrowserRouter>
        <Routes>
          <Route
            element={
              <AppShell
                username={username}
                onLogout={handleLogout}
                onSessionExpired={handleSessionExpired}
              />
            }
          >
            <Route index element={<DashboardPage />} />
            <Route path="skills" element={<SkillsListPage />} />
            <Route path="skills/:name" element={<SkillDetailPage />} />
            <Route path="stations" element={<StationsListPage />} />
            <Route path="stations/:name" element={<StationDetailPage />} />
            <Route path="workers" element={<WorkersListPage />} />
            <Route path="workers/:name" element={<WorkerDetailPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </SSEProvider>
  );
}

export default App;
