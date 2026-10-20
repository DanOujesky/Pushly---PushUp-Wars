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
  assert.deepEqual(p.flags, []);
});

Deno.test("hard failures are stored unverified with hard flags", async () => {
  const { d, calls } = deps({ now: () => byId("machine-gun").receivedAtMs });
  await handler(post(byId("machine-gun").log), d);
  assert.equal(calls[0].verified, false);
  assert.deepEqual(calls[0].flags, [
    { type: "rate_sustained", severity: "hard", details: {} },
    { type: "fast_reps", severity: "soft", details: {} },
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
