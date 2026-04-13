import { useState, useCallback } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router";
import LoginPage from "./components/LoginPage";
import AppShell from "./components/AppShell";
import DashboardPage from "./components/DashboardPage";
import SkillsListPage from "./components/SkillsListPage";
import SkillDetailPage from "./components/SkillDetailPage";
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
          <Route path="skills/:id" element={<SkillDetailPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
