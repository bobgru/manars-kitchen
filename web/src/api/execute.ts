import { apiFetch } from "./client";

export async function executeCommand(command: string): Promise<string> {
  const response = await apiFetch("/rpc/execute", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command }),
  });

  if (!response.ok) {
    throw new Error(`Execute failed: ${response.status}`);
  }

  return response.text();
}
