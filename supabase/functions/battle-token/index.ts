import { type Battle, handler } from "./handler.ts";

// Secrets: LIVEKIT_URL (wss://…livekit.cloud), LIVEKIT_API_KEY, LIVEKIT_API_SECRET (docs/RELEASING.md → Battles).
const url = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const lkUrl = Deno.env.get("LIVEKIT_URL");
const lkKey = Deno.env.get("LIVEKIT_API_KEY");
const lkSecret = Deno.env.get("LIVEKIT_API_SECRET");

async function rest(path: string): Promise<unknown[] | null> {
  const res = await fetch(`${url}/rest/v1/${path}`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  if (!res.ok) return null;
  const rows = await res.json();
  return Array.isArray(rows) ? rows : null;
}

async function getUser(authorization: string) {
  const res = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: authorization } });
  if (!res.ok) return null;
  const body = await res.json();
  if (typeof body?.id !== "string") return null;
  const rows = await rest(`profiles?id=eq.${body.id}&select=username`);
  const username = (rows?.[0] as { username?: string } | undefined)?.username ?? "player";
  return { id: body.id as string, username };
}

async function getBattle(id: string): Promise<Battle | null> {
  const rows = await rest(
    `battles?id=eq.${encodeURIComponent(id)}&select=id,player_a,player_b,status,ranked,livekit_room`,
  );
  const b = rows?.[0] as Record<string, unknown> | undefined;
  return b
    ? {
      id: String(b.id),
      playerA: (b.player_a as string | null) ?? null,
      playerB: (b.player_b as string | null) ?? null,
      status: String(b.status),
      ranked: Boolean(b.ranked),
      room: (b.livekit_room as string | null) ?? null,
    }
    : null;
}

Deno.serve((req) =>
  handler(req, {
    now: Date.now,
    getUser,
    getBattle,
    livekit: lkUrl && lkKey && lkSecret ? { url: lkUrl, apiKey: lkKey, apiSecret: lkSecret } : null,
  })
);
