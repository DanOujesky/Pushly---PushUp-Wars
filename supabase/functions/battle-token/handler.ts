// battle-token: LiveKit room token for a battle participant (doc 07 §4.1, roadmap P7-05).
// Grants only this battle's room, TTL 15 min. Ranked battles publish no audio (doc 07 §5).
import { b64url } from "../_shared/jwt.ts";
import { ErrorCode, errorResponse, json, preflight } from "../_shared/http.ts";

export interface Battle {
  id: string;
  playerA: string | null;
  playerB: string | null;
  status: string;
  ranked: boolean;
  room: string | null;
}

export interface Deps {
  now: () => number;
  getUser: (authorization: string) => Promise<{ id: string; username: string } | null>;
  getBattle: (id: string) => Promise<Battle | null>;
  livekit: { url: string; apiKey: string; apiSecret: string } | null;
}

const OPEN = new Set(["lobby", "ready_check", "countdown", "live", "round_rest", "finished"]);

/** LiveKit access token: HS256 JWT with a video grant. */
export async function livekitToken(
  apiKey: string,
  apiSecret: string,
  identity: string,
  name: string,
  room: string,
  canPublishAudio: boolean,
  nowMs: number,
): Promise<string> {
  const iat = Math.floor(nowMs / 1000);
  const claims = {
    iss: apiKey,
    sub: identity,
    name,
    nbf: iat - 10,
    exp: iat + 15 * 60,
    video: {
      room,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      canPublishSources: canPublishAudio ? ["camera", "microphone"] : ["camera"],
    },
  };
  const input = `${b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }))}.${b64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(input)));
  return `${input}.${b64url(sig)}`;
}

export async function handler(req: Request, deps: Deps): Promise<Response> {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return errorResponse(ErrorCode.VALIDATION_FAILED, "POST only");
  const user = await deps.getUser(req.headers.get("authorization") ?? "");
  if (!user) return errorResponse(ErrorCode.UNAUTHENTICATED, "sign in first");
  const body = await req.json().catch(() => null);
  const battleId = typeof body?.battleId === "string" ? body.battleId : "";
  if (!/^[0-9a-f-]{36}$/i.test(battleId)) return errorResponse(ErrorCode.VALIDATION_FAILED, "battleId missing");
  const battle = await deps.getBattle(battleId);
  if (!battle || (battle.playerA !== user.id && battle.playerB !== user.id)) {
    return errorResponse(ErrorCode.NOT_FOUND, "battle not found");
  }
  if (!OPEN.has(battle.status)) return errorResponse(ErrorCode.CONFLICT, "battle is over");
  if (!deps.livekit) return errorResponse(ErrorCode.INTERNAL, "video is not configured yet");
  const room = battle.room ?? `battle-${battle.id}`;
  const token = await livekitToken(
    deps.livekit.apiKey,
    deps.livekit.apiSecret,
    user.id,
    user.username,
    room,
    !battle.ranked,
    deps.now(),
  );
  return json({ url: deps.livekit.url, token, room, expiresInS: 900 });
}
