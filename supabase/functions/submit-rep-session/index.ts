import { type ApplyResult, handler } from "./handler.ts";

// Wiring for the hosted function. Supabase provides these env vars to every Edge Function.
const url = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

async function getUser(authorization: string): Promise<{ id: string } | null> {
  const res = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: authorization } });
  if (!res.ok) return null;
  const body = await res.json();
  return typeof body?.id === "string" ? { id: body.id } : null;
}

async function apply(payload: Record<string, unknown>): Promise<ApplyResult> {
  const res = await fetch(`${url}/rest/v1/rpc/apply_validated_session`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p: payload }),
  });
  const body = await res.json().catch(() => null);
  if (res.ok) return { ok: true, result: body };
  const message = String(body?.message ?? res.statusText);
  for (const code of ["duplicate_log", "session_conflict", "unknown_user"] as const) {
    if (message.includes(code)) return { ok: false, code, message };
  }
  console.error("apply_validated_session failed", res.status, message);
  return { ok: false, code: "internal", message };
}

Deno.serve((req) => handler(req, { now: Date.now, getUser, apply }));
