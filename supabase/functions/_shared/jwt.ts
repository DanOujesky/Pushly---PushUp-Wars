// Minimal JWT signing for the push providers (APNs ES256, Google OAuth RS256). WebCrypto only, no dependencies.

type Bytes = Uint8Array<ArrayBuffer>;

export function b64url(data: Bytes | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** PEM (PKCS#8, "-----BEGIN PRIVATE KEY-----") → DER bytes. CR/LF and escaped "\n" are tolerated. */
export function pemToDer(pem: string): Bytes {
  const body = pem.replaceAll("\\n", "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const s = atob(body);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

export async function signJwt(
  header: Record<string, unknown>,
  claims: Record<string, unknown>,
  pem: string,
  alg: "ES256" | "RS256",
): Promise<string> {
  const input = `${b64url(JSON.stringify({ ...header, alg, typ: "JWT" }))}.${b64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    alg === "ES256" ? { name: "ECDSA", namedCurve: "P-256" } : { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    alg === "ES256" ? { name: "ECDSA", hash: "SHA-256" } : { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(input),
  );
  return `${input}.${b64url(new Uint8Array(sig))}`;
}
