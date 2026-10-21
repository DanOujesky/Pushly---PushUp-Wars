// APNs (token auth, HTTP/2 via fetch) and FCM HTTP v1. Each returns a delivery outcome; "dead" = the token is gone.
import { signJwt } from "../_shared/jwt.ts";
import type { Rendered } from "./messages.ts";

export type Outcome = { ok: true } | { ok: false; dead: boolean; retry: boolean; error: string };

export interface ApnsConfig {
  keyP8: string;
  keyId: string;
  teamId: string;
  topic: string;
  sandbox: boolean;
}

export interface FcmConfig {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

type Fetch = typeof fetch;

let apnsJwt: { token: string; at: number } | null = null;

/** APNs provider token, reused for 40 minutes (Apple allows 20–60). */
export async function apnsToken(cfg: ApnsConfig, nowMs: number): Promise<string> {
  if (apnsJwt && nowMs - apnsJwt.at < 40 * 60_000) return apnsJwt.token;
  const token = await signJwt(
    { kid: cfg.keyId },
    { iss: cfg.teamId, iat: Math.floor(nowMs / 1000) },
    cfg.keyP8,
    "ES256",
  );
  apnsJwt = { token, at: nowMs };
  return token;
}

export function apnsPayload(msg: Rendered, type: string, silent: boolean, extra: Record<string, unknown>) {
  const aps: Record<string, unknown> = silent ? { "content-available": 1 } : {
    alert: { title: msg.title, body: msg.body },
    sound: "default",
    "interruption-level": msg.urgent ? "time-sensitive" : "active",
    "thread-id": type,
  };
  return { aps, link: msg.link, type, ...extra };
}

export async function sendApns(
  cfg: ApnsConfig,
  deviceToken: string,
  body: unknown,
  opts: { silent: boolean; collapseId?: string | null; nowMs: number },
  f: Fetch = fetch,
): Promise<Outcome> {
  const host = cfg.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const headers: Record<string, string> = {
    authorization: `bearer ${await apnsToken(cfg, opts.nowMs)}`,
    "apns-topic": cfg.topic,
    "apns-push-type": opts.silent ? "background" : "alert",
    "apns-priority": opts.silent ? "5" : "10",
    "content-type": "application/json",
  };
  if (opts.collapseId) headers["apns-collapse-id"] = opts.collapseId.slice(0, 64);
  try {
    const res = await f(`https://${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    if (res.ok) return { ok: true };
    const reason = String((await res.json().catch(() => ({})))?.reason ?? res.status);
    const dead = res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered";
    return {
      ok: false,
      dead,
      retry: !dead && (res.status === 429 || res.status >= 500),
      error: `apns ${res.status} ${reason}`,
    };
  } catch (e) {
    return { ok: false, dead: false, retry: true, error: `apns ${e instanceof Error ? e.message : String(e)}` };
  }
}

let fcmAccess: { token: string; until: number } | null = null;

/** OAuth access token for FCM from the service account (JWT bearer grant), cached until 5 min before expiry. */
export async function fcmAccessToken(cfg: FcmConfig, nowMs: number, f: Fetch = fetch): Promise<string> {
  if (fcmAccess && nowMs < fcmAccess.until) return fcmAccess.token;
  const iat = Math.floor(nowMs / 1000);
  const assertion = await signJwt(
    {},
    {
      iss: cfg.clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat,
      exp: iat + 3600,
    },
    cfg.privateKey,
    "RS256",
  );
  const res = await f("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
  });
  if (!res.ok) throw new Error(`google oauth ${res.status}`);
  const body = await res.json();
  fcmAccess = { token: String(body.access_token), until: nowMs + (Number(body.expires_in ?? 3600) - 300) * 1000 };
  return fcmAccess.token;
}

export function fcmMessage(token: string, msg: Rendered, type: string, silent: boolean, collapseKey?: string | null) {
  const data: Record<string, string> = { link: msg.link, type };
  return {
    message: {
      token,
      data: silent ? data : { ...data, title: msg.title, body: msg.body },
      ...(silent ? {} : { notification: { title: msg.title, body: msg.body } }),
      android: {
        priority: msg.urgent ? "HIGH" : "NORMAL",
        ...(collapseKey ? { collapse_key: collapseKey.slice(0, 64) } : {}),
        ...(silent ? {} : { notification: { channel_id: msg.urgent ? "pushly_urgent" : "pushly_activity" } }),
      },
    },
  };
}

export async function sendFcm(cfg: FcmConfig, body: unknown, nowMs: number, f: Fetch = fetch): Promise<Outcome> {
  try {
    const access = await fcmAccessToken(cfg, nowMs, f);
    const res = await f(`https://fcm.googleapis.com/v1/projects/${cfg.projectId}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${access}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (res.ok) return { ok: true };
    const err = await res.json().catch(() => ({}));
    const status = String(err?.error?.status ?? res.status);
    const dead = res.status === 404 || status === "UNREGISTERED" ||
      (res.status === 400 && JSON.stringify(err).includes("registration token"));
    return {
      ok: false,
      dead,
      retry: !dead && (res.status === 429 || res.status >= 500),
      error: `fcm ${res.status} ${status}`,
    };
  } catch (e) {
    return { ok: false, dead: false, retry: true, error: `fcm ${e instanceof Error ? e.message : String(e)}` };
  }
}

/** Test hook: forget cached provider tokens. */
export function resetProviderCaches() {
  apnsJwt = null;
  fcmAccess = null;
}
