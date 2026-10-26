import nodeAssert from "node:assert/strict";

const assertEquals = (a: unknown, b: unknown) => nodeAssert.deepStrictEqual(a, b);
const assert: (v: unknown) => asserts v = (v) => nodeAssert.ok(v);
import { deliver, type Deps, handler, type Job } from "./handler.ts";
import { render } from "./messages.ts";
import { apnsPayload, fcmMessage, resetProviderCaches, sendApns, sendFcm } from "./providers.ts";
import { b64url } from "../_shared/jwt.ts";

const job = (over: Partial<Job> = {}): Job => ({
  id: 1,
  userId: "u",
  type: "kudos",
  category: "social",
  payload: { username: "tom" },
  silent: false,
  collapseKey: "kudos:2026-10-21",
  devices: [{ id: "d1", platform: "ios", token: "tok" }],
  ...over,
});

const ok = () => Promise.resolve({ ok: true as const });

Deno.test("render: known types, unknown is null", () => {
  assertEquals(render("kudos", { username: "tom" })?.body, "tom gave you kudos.");
  assertEquals(render("friend_request", {})?.body, "A friend wants to be friends on Pushly.");
  assert(render("alarms_running_out", {})?.urgent);
  assertEquals(render("nope", {}), null);
});

Deno.test("deliver: success, missing devices, unknown type, unconfigured platform", async () => {
  const deps = { sendIos: ok, sendAndroid: null } as unknown as Deps;
  const { results } = await deliver([
    job(),
    job({ id: 2, devices: [] }),
    job({ id: 3, type: "nope" }),
    job({ id: 4, devices: [{ id: "d2", platform: "android", token: "t" }] }),
  ], deps);
  assertEquals(results, [
    { id: 1, ok: true },
    { id: 2, ok: false, error: "no_device", retry: false },
    { id: 3, ok: false, error: "unknown type nope", retry: false },
    { id: 4, ok: false, error: "android_not_configured", retry: false },
  ]);
});

Deno.test("deliver: one good device is enough; dead tokens reported", async () => {
  const deps = {
    sendIos: () => Promise.resolve({ ok: false, dead: true, retry: false, error: "apns 410 Unregistered" }),
    sendAndroid: ok,
  } as unknown as Deps;
  const { results, dead } = await deliver([
    job({ devices: [{ id: "d1", platform: "ios", token: "a" }, { id: "d2", platform: "android", token: "b" }] }),
  ], deps);
  assertEquals(results, [{ id: 1, ok: true }]);
  assertEquals(dead, ["d1"]);
});

Deno.test("handler: service role only, claims and finishes", async () => {
  let finished: unknown = null;
  const deps: Deps = {
    isServiceRole: (a) => a === "Bearer svc",
    claim: () => Promise.resolve([job()]),
    finish: (r, d) => {
      finished = { r, d };
      return Promise.resolve();
    },
    sendIos: ok,
    sendAndroid: ok,
  };
  const denied = await handler(
    new Request("http://x", { method: "POST", headers: { authorization: "Bearer user" } }),
    deps,
  );
  assertEquals(denied.status, 403);
  const res = await handler(
    new Request("http://x", { method: "POST", headers: { authorization: "Bearer svc" } }),
    deps,
  );
  assertEquals(await res.json(), { claimed: 1, sent: 1, dead: 0 });
  assertEquals(finished, { r: [{ id: 1, ok: true }], d: [] });
});

async function p256Pem(): Promise<string> {
  const k = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", k.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
}

async function rsaPem(): Promise<string> {
  const k = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", k.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
}

Deno.test("APNs: request shape, JWT header, dead token", async () => {
  resetProviderCaches();
  const cfg = { keyP8: await p256Pem(), keyId: "KEY123", teamId: "TEAM456", topic: "app.pushly", sandbox: true };
  const calls: { url: string; init: RequestInit }[] = [];
  const fake = (status: number, body: unknown) => (u: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(u), init: init ?? {} });
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
  const msg = render("kudos", { username: "tom" });
  assert(msg);
  const out = await sendApns(cfg, "abc", apnsPayload(msg, "kudos", false, {}), {
    silent: false,
    collapseId: "k",
    nowMs: 1_000_000,
  }, fake(200, {}) as typeof fetch);
  assertEquals(out, { ok: true });
  assertEquals(calls[0].url, "https://api.sandbox.push.apple.com/3/device/abc");
  const h = calls[0].init.headers as Record<string, string>;
  assertEquals(h["apns-topic"], "app.pushly");
  assertEquals(h["apns-collapse-id"], "k");
  const header = JSON.parse(
    atob(h.authorization.split(" ")[1].split(".")[0].replaceAll("-", "+").replaceAll("_", "/")),
  );
  assertEquals(header, { kid: "KEY123", alg: "ES256", typ: "JWT" });
  const body = JSON.parse(String(calls[0].init.body));
  assertEquals(body.aps.alert.title, "👊 Kudos!");
  assertEquals(body.link, "pushly://friends");
  const gone = await sendApns(
    cfg,
    "abc",
    {},
    { silent: true, nowMs: 1_000_000 },
    fake(410, { reason: "Unregistered" }) as typeof fetch,
  );
  assertEquals(gone, { ok: false, dead: true, retry: false, error: "apns 410 Unregistered" });
});

Deno.test("FCM: OAuth token exchange then message send; 404 = dead", async () => {
  resetProviderCaches();
  const cfg = { projectId: "pushly-123", clientEmail: "svc@pushly.iam", privateKey: await rsaPem() };
  const urls: string[] = [];
  const fake = (sendStatus: number) => (u: string | URL | Request, init?: RequestInit) => {
    urls.push(String(u));
    if (String(u).includes("oauth2")) {
      const assertion = new URLSearchParams(String(init?.body)).get("assertion") ?? "";
      assertEquals(assertion.split(".").length, 3);
      return Promise.resolve(new Response(JSON.stringify({ access_token: "ya29", expires_in: 3600 }), { status: 200 }));
    }
    assertEquals((init?.headers as Record<string, string>).authorization, "Bearer ya29");
    return Promise.resolve(new Response(JSON.stringify({ error: { status: "NOT_FOUND" } }), { status: sendStatus }));
  };
  const msg = render("friend_request", { username: "ana" });
  assert(msg);
  const m = fcmMessage("tok", msg, "friend_request", false, "friend:x");
  assertEquals(m.message.android.priority, "NORMAL");
  assertEquals(await sendFcm(cfg, m, 0, fake(200) as typeof fetch), { ok: true });
  assertEquals(urls, [
    "https://oauth2.googleapis.com/token",
    "https://fcm.googleapis.com/v1/projects/pushly-123/messages:send",
  ]);
  const out = await sendFcm(cfg, m, 1, fake(404) as typeof fetch);
  assertEquals(out.ok ? null : out.dead, true);
});

Deno.test("b64url has no padding", () => {
  assertEquals(b64url("a"), "YQ");
});

Deno.test("clan war pushes (D-078)", () => {
  const started = render("clan_war_started", {
    clanName: "Iron Wolves",
    opponents: "Night Owls, Red Fox",
    warId: "w1",
  });
  assertEquals(started?.link, "pushly://clan/war/w1");
  assertEquals(started?.body.includes("Night Owls, Red Fox"), true);
  const won = render("clan_war_result", { rank: 1, of: 4, delta: 45, warId: "w1" });
  assertEquals(won?.title, "🏆 Clan War won!");
  assertEquals(won?.body, "🏆 We won the Clan War (+45 clan trophies). The next war starts Monday.");
  const third = render("clan_war_result", { rank: 3, of: 4, delta: -15, warId: "w1" });
  assertEquals(third?.body, "We finished #3 of 4 (-15 clan trophies). The next war starts Monday.");
});
