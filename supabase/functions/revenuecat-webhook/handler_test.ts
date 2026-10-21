import assert from "node:assert/strict";
import { handler } from "./handler.ts";

const event = { id: "e1", type: "INITIAL_PURCHASE", app_user_id: "u" };
const post = (auth: string, body: unknown) =>
  new Request("http://x", { method: "POST", headers: { authorization: auth }, body: JSON.stringify(body) });

Deno.test("applies events with the right secret", async () => {
  let seen: unknown = null;
  const res = await handler(post("Bearer s3cret", { event }), {
    secret: "Bearer s3cret",
    apply: (e) => {
      seen = e;
      return Promise.resolve("applied");
    },
  });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { outcome: "applied" });
  assert.deepEqual(seen, event);
});

Deno.test("wrong or missing secret → 401; no event → 400; DB error → 500", async () => {
  const deps = { secret: "Bearer s3cret", apply: () => Promise.resolve("applied") };
  assert.equal((await handler(post("Bearer nope", { event }), deps)).status, 401);
  assert.equal((await handler(post("Bearer s3cret", { event }), { ...deps, secret: null })).status, 401);
  assert.equal((await handler(post("Bearer s3cret", {}), deps)).status, 400);
  assert.equal(
    (await handler(post("Bearer s3cret", { event }), { ...deps, apply: () => Promise.reject(new Error("db")) })).status,
    500,
  );
});
