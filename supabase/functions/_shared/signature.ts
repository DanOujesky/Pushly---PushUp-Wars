// ECDSA P-256 / SHA-256 signatures of rep logs (doc 06 §3). The app signs the exact UTF-8 bytes of the log JSON it
// sends, so no canonical-JSON rules are needed. iOS CryptoKit gives raw r‖s (64 bytes), Android Keystore gives DER;
// both are accepted.

type Bytes = Uint8Array<ArrayBuffer>;

export function b64ToBytes(b64: string): Bytes {
  const s = atob(b64);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

/** DER `SEQUENCE { INTEGER r, INTEGER s }` → raw 64-byte r‖s (WebCrypto's ECDSA format). */
export function derToRaw(der: Uint8Array): Bytes | null {
  if (der.length < 8 || der[0] !== 0x30) return null;
  let i = 2;
  if (der[1] & 0x80) i = 2 + (der[1] & 0x7f);
  const out = new Uint8Array(64);
  for (let k = 0; k < 2; k++) {
    if (der[i] !== 0x02) return null;
    const len = der[i + 1];
    let start = i + 2;
    let n = len;
    while (n > 32 && der[start] === 0) {
      start++;
      n--;
    }
    if (n > 32) return null;
    out.set(der.subarray(start, start + n), k * 32 + (32 - n));
    i = i + 2 + len;
  }
  return out;
}

export async function verifyP256(spkiB64: string, data: Bytes, signatureB64: string): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey(
      "spki",
      b64ToBytes(spkiB64),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      [
        "verify",
      ],
    );
    let sig = b64ToBytes(signatureB64);
    if (sig.length !== 64) {
      const raw = derToRaw(sig);
      if (!raw) return false;
      sig = raw;
    }
    return await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, sig, data);
  } catch {
    return false;
  }
}
