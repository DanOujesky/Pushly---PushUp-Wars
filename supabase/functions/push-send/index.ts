import { type Deps, handler, type Job, type Result } from "./handler.ts";
import { render } from "./messages.ts";
import { type ApnsConfig, apnsPayload, type FcmConfig, fcmMessage, sendApns, sendFcm } from "./providers.ts";

// Secrets (supabase secrets set …, docs/RELEASING.md): APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID, APNS_SANDBOX ("true" for
// development builds) and FCM_SERVICE_ACCOUNT (the service-account JSON). Missing secrets just skip that platform.
const url = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function apnsConfig(): ApnsConfig | null {
  const keyP8 = Deno.env.get("APNS_KEY_P8");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  if (!keyP8 || !keyId || !teamId) return null;
  return { keyP8, keyId, teamId, topic: "app.pushly", sandbox: Deno.env.get("APNS_SANDBOX") === "true" };
}

function fcmConfig(): FcmConfig | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw);
    return { projectId: sa.project_id, clientEmail: sa.client_email, privateKey: sa.private_key };
  } catch {
    console.error("FCM_SERVICE_ACCOUNT is not valid JSON");
    return null;
  }
}

async function rpc(name: string, body: unknown): Promise<unknown> {
  const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${name} ${res.status} ${await res.text()}`);
  return res.status === 204 ? null : await res.json();
}

const apns = apnsConfig();
const fcm = fcmConfig();

const deps: Deps = {
  isServiceRole: (authorization) => serviceKey.length > 0 && authorization === `Bearer ${serviceKey}`,
  claim: async (limit) => (await rpc("claim_push_batch", { p_limit: limit })) as Job[],
  finish: async (results: Result[], dead: string[]) => {
    await rpc("finish_push", { results, dead_devices: dead });
  },
  sendIos: apns
    ? (job, device) => {
      const msg = render(job.type, job.payload);
      if (!msg) return Promise.resolve({ ok: false, dead: false, retry: false, error: "unknown type" });
      return sendApns(apns, device.token, apnsPayload(msg, job.type, job.silent, {}), {
        silent: job.silent,
        collapseId: job.collapseKey,
        nowMs: Date.now(),
      });
    }
    : null,
  sendAndroid: fcm
    ? (job, device) => {
      const msg = render(job.type, job.payload);
      if (!msg) return Promise.resolve({ ok: false, dead: false, retry: false, error: "unknown type" });
      return sendFcm(fcm, fcmMessage(device.token, msg, job.type, job.silent, job.collapseKey), Date.now());
    }
    : null,
};

Deno.serve((req) => handler(req, deps));
