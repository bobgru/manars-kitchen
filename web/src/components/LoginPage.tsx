import { useState, type FormEvent } from "react";

interface LoginPageProps {
  onLogin: (token: string, username: string, role: string) => void;
}

export default function LoginPage({ onLogin }: LoginPageProps) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const response = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });

      if (!response.ok) {
        if (response.status === 401) {
          setError("Invalid username or password");
        } else {
          setError(`Login failed (${response.status})`);
        }
        return;
      }

      const data = await response.json();
      sessionStorage.setItem("token", data.token);
      sessionStorage.setItem("username", data.user.username);
      sessionStorage.setItem("role", data.user.role);
      onLogin(data.token, data.user.username, data.user.role);
    } catch {
      setError("Network error — is the server running?");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <form className="login-form" onSubmit={handleSubmit}>
        <h1>Manar's Kitchen</h1>
        {error && <div className="login-error">{error}</div>}
        <label>
          Username
          <input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoFocus
            disabled={loading}
          />
        </label>
        <label>
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={loading}
          />
        </label>
        <button type="submit" disabled={loading || !username || !password}>
          {loading ? "Logging in..." : "Log in"}
        </button>
      </form>
    </div>
  );
}
