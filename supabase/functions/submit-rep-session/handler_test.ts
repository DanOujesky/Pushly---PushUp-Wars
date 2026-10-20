import assert from "node:assert/strict";
import { type Deps, handler } from "./handler.ts";

const { cases } = JSON.parse(
  await Deno.readTextFile(new URL("../../../shared/test-vectors/rep-log/cases.json", import.meta.url)),
);
const byId = (id: string) => structuredClone(cases.find((c: { id: string }) => c.id === id));

function deps(overrides: Partial<Deps> = {}) {
  const calls: Record<string, unknown>[] = [];
  const d: Deps = {
    now: () => byId("clean-anchored").receivedAtMs,
    getUser: (auth) => Promise.resolve(auth === "Bearer good" ? { id: "u1" } : null),
    getDevice: () => Promise.resolve(null),
    apply: (p) => {
      calls.push(p);
      return Promise.resolve({
        ok: true,
        result: { sessionId: p.session && (p.session as { sessionId: string }).sessionId },
      });
    },
    ...overrides,
  };
  return { d, calls };
}

const post = (body: unknown, auth = "Bearer good") =>
  new Request("http://localhost/submit-rep-session", {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

Deno.test("requires a signed-in user", async () => {
  const { d } = deps();
  const res = await handler(post(byId("clean-anchored").log, "Bearer bad"), d);
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error.code, "UNAUTHENTICATED");
});

Deno.test("rejects malformed logs with the field list", async () => {
  const { d, calls } = deps();
  const res = await handler(post({ sessionId: "x" }), d);
  assert.equal(res.status, 422);
  assert.ok((await res.json()).error.details.fields.includes("sessionId"));
  assert.equal(calls.length, 0);
  assert.equal((await handler(post("{not json"), d)).status, 422);
});

Deno.test("a clean log is applied verified, in server time", async () => {
  const { d, calls } = deps();
  const c = byId("clean-anchored");
  const res = await handler(post(c.log), d);
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  const p = calls[0];
  assert.equal(p.userId, "u1");
  assert.equal(p.verified, true);
  assert.deepEqual(p.session, c.expected.session);
  assert.deepEqual(p.flags, [{ type: "unsigned_log", severity: "soft", details: {} }], "bare logs are flagged softly");
});

Deno.test("hard failures are stored unverified with hard flags", async () => {
  const { d, calls } = deps({ now: () => byId("machine-gun").receivedAtMs });
  await handler(post(byId("machine-gun").log), d);
  assert.equal(calls[0].verified, false);
  assert.deepEqual(calls[0].flags, [
    { type: "rate_sustained", severity: "hard", details: {} },
    { type: "fast_reps", severity: "soft", details: {} },
    { type: "unsigned_log", severity: "soft", details: {} },
  ]);
});

Deno.test("held sessions are unverified with a soft flag", async () => {
  const { d, calls } = deps();
  await handler(post(byId("long-set-held").log), d);
  assert.equal(calls[0].verified, false);
  assert.equal((calls[0].verification as { hold: string }).hold, "long_set");
});

Deno.test("a replayed log maps to CONFLICT", async () => {
  const { d } = deps({ apply: () => Promise.resolve({ ok: false, code: "duplicate_log", message: "duplicate_log" }) });
  const res = await handler(post(byId("clean-anchored").log), d);
  assert.equal(res.status, 409);
  assert.equal((await res.json()).error.code, "CONFLICT");
});

Deno.test("database errors are retryable INTERNAL", async () => {
  const { d } = deps({ apply: () => Promise.resolve({ ok: false, code: "internal", message: "boom" }) });
  const body = await (await handler(post(byId("clean-anchored").log), d)).json();
  assert.equal(body.error.code, "INTERNAL");
  assert.equal(body.error.retryable, true);
});

const b64 = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b)));
const DEVICE = "d0000000-0000-4000-8000-000000000001";

async function signedSetup(owner = "u1") {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const spki = b64(await crypto.subtle.exportKey("spki", kp.publicKey));
  const text = JSON.stringify(byId("clean-anchored").log);
  const sig = b64(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, kp.privateKey, new TextEncoder().encode(text)),
  );
  const { d, calls } = deps({
    getDevice: (id) => Promise.resolve(id === DEVICE ? { userId: owner, publicKey: spki, revokedAt: null } : null),
  });
  return { d, calls, text, sig };
}

Deno.test("a correctly signed log is verified and bound to the device", async () => {
  const { d, calls, text, sig } = await signedSetup();
  const res = await handler(post({ log: text, signature: sig, deviceId: DEVICE }), d);
  assert.equal(res.status, 200);
  assert.equal(calls[0].verified, true);
  assert.equal(calls[0].deviceId, DEVICE);
  assert.equal(calls[0].signature, sig);
  assert.equal((calls[0].verification as { integrity: string }).integrity, "signed");
  assert.deepEqual(calls[0].flags, []);
});

Deno.test("a tampered signed log fails hard", async () => {
  const { d, calls, text, sig } = await signedSetup();
  await handler(post({ log: text.replace('"quality":85', '"quality":99'), signature: sig, deviceId: DEVICE }), d);
  assert.equal(calls[0].verified, false);
  assert.equal((calls[0].flags as { type: string }[])[0].type, "signature_invalid");
  assert.equal(calls[0].deviceId, null);
});

Deno.test("someone else's device key is refused", async () => {
  const { d, calls, text, sig } = await signedSetup("u2");
  await handler(post({ log: text, signature: sig, deviceId: DEVICE }), d);
  assert.equal(calls[0].verified, false);
  assert.equal((calls[0].flags as { type: string }[])[0].type, "device_unknown");
});
