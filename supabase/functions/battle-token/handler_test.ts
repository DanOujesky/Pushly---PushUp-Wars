import assert from "node:assert/strict";
import { type Deps, handler, livekitToken } from "./handler.ts";

const battle = {
  id: "b0000000-0000-4000-8000-000000000001",
  playerA: "ana",
  playerB: "tom",
  status: "lobby",
  ranked: true,
  room: "battle-1",
};

function deps(over: Partial<Deps> = {}): Deps {
  return {
    now: () => 1_800_000_000_000,
    getUser: (a) => Promise.resolve(a === "Bearer ana" ? { id: "ana", username: "AnaFit" } : null),
    getBattle: () => Promise.resolve(battle),
    livekit: { url: "wss://x.livekit.cloud", apiKey: "APIkey", apiSecret: "secret-secret-secret" },
    ...over,
  };
}

const req = (auth: string, body: unknown) =>
  new Request("http://x", { method: "POST", headers: { authorization: auth }, body: JSON.stringify(body) });

function claims(token: string) {
  const p = token.split(".")[1].replaceAll("-", "+").replaceAll("_", "/");
  return JSON.parse(atob(p + "=".repeat((4 - (p.length % 4)) % 4)));
}

Deno.test("participants get a room token; ranked = no microphone", async () => {
  const res = await handler(req("Bearer ana", { battleId: battle.id }), deps());
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.room, "battle-1");
  const c = claims(body.token);
  assert.equal(c.sub, "ana");
  assert.equal(c.iss, "APIkey");
  assert.equal(c.exp - c.nbf, 910);
  assert.deepEqual(c.video.canPublishSources, ["camera"]);
  assert.equal(c.video.room, "battle-1");
});

Deno.test("signature verifies with the secret", async () => {
  const t = await livekitToken("k", "s3cret", "u", "n", "r", true, 0);
  const [h, p, s] = t.split(".");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode("s3cret"),
    { name: "HMAC", hash: "SHA-256" },
    false,
    [
      "verify",
    ],
  );
  const sig = Uint8Array.from(
    atob(s.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (s.length % 4)) % 4)),
    (c) => c.charCodeAt(0),
  );
  assert.ok(await crypto.subtle.verify("HMAC", key, sig, new TextEncoder().encode(`${h}.${p}`)));
});

Deno.test("outsiders, finished battles, missing config", async () => {
  assert.equal((await handler(req("Bearer nope", { battleId: battle.id }), deps())).status, 401);
  assert.equal(
    (await handler(
      req("Bearer ana", { battleId: battle.id }),
      deps({ getBattle: () => Promise.resolve({ ...battle, playerA: "x" }) }),
    ))
      .status,
    404,
  );
  assert.equal(
    (await handler(
      req("Bearer ana", { battleId: battle.id }),
      deps({ getBattle: () => Promise.resolve({ ...battle, status: "settled" }) }),
    ))
      .status,
    409,
  );
  assert.equal((await handler(req("Bearer ana", { battleId: battle.id }), deps({ livekit: null }))).status, 500);
  assert.equal((await handler(req("Bearer ana", { battleId: "x" }), deps())).status, 422);
});
