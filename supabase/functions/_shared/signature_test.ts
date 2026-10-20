import assert from "node:assert/strict";
import { derToRaw, verifyP256 } from "./signature.ts";

const b64 = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b)));

async function keyPair() {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  return { kp, spki: b64(await crypto.subtle.exportKey("spki", kp.publicKey)) };
}

/** raw r‖s → DER, like Android Keystore produces. */
function rawToDer(raw: Uint8Array): Uint8Array {
  const int = (x: Uint8Array) => {
    let v = Array.from(x);
    while (v.length > 1 && v[0] === 0) v = v.slice(1);
    if (v[0] & 0x80) v = [0, ...v];
    return [0x02, v.length, ...v];
  };
  const body = [...int(raw.subarray(0, 32)), ...int(raw.subarray(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}

Deno.test("verifies raw (iOS) and DER (Android) signatures over the exact log bytes", async () => {
  const { kp, spki } = await keyPair();
  const data = new TextEncoder().encode('{"sessionId":"x","reps":[]}');
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, kp.privateKey, data));
  assert.equal(await verifyP256(spki, data, b64(raw)), true);
  assert.equal(await verifyP256(spki, data, b64(rawToDer(raw))), true);
  assert.deepEqual(derToRaw(rawToDer(raw)), raw);
});

Deno.test("rejects tampered logs, other keys and garbage", async () => {
  const { kp, spki } = await keyPair();
  const other = await keyPair();
  const data = new TextEncoder().encode('{"reps":20}');
  const sig = b64(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, kp.privateKey, data));
  assert.equal(await verifyP256(spki, new TextEncoder().encode('{"reps":200}'), sig), false);
  assert.equal(await verifyP256(other.spki, data, sig), false);
  assert.equal(await verifyP256(spki, data, "AAAA"), false);
  assert.equal(await verifyP256("not a key", data, sig), false);
});
