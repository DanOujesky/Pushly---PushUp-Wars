import assert from "node:assert/strict";
import { handler } from "./handler.ts";

Deno.test("GET returns ok and the injected server time", async () => {
  const res = handler(new Request("http://localhost/health"), () => 1_700_000_000_000);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, serverMs: 1_700_000_000_000 });
});

Deno.test("OPTIONS answers the CORS preflight", () => {
  const res = handler(new Request("http://localhost/health", { method: "OPTIONS" }));
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("other methods get the standard error shape", async () => {
  const res = handler(new Request("http://localhost/health", { method: "PUT" }));
  assert.equal(res.status, 422);
  const body = await res.json();
  assert.equal(body.error.code, "VALIDATION_FAILED");
  assert.equal(body.error.retryable, false);
});

Deno.test("POST works too (SDK function invoke)", async () => {
  const res = handler(new Request("http://localhost/health", { method: "POST" }), () => 42);
  assert.deepEqual(await res.json(), { ok: true, serverMs: 42 });
});
