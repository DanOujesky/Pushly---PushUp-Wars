// revenuecat-webhook: RevenueCat → entitlements → profiles.is_pro (doc 13 §2, roadmap P10-01).
// RevenueCat sends the configured Authorization header value; we compare it in constant time.
import { json } from "../_shared/http.ts";

export interface Deps {
  secret: string | null;
  apply: (event: Record<string, unknown>) => Promise<string>;
}

function sameText(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export async function handler(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!deps.secret || !sameText(req.headers.get("authorization") ?? "", deps.secret)) {
    return json({ error: "unauthorized" }, 401);
  }
  const body = await req.json().catch(() => null);
  const event = body?.event;
  if (!event || typeof event !== "object" || typeof event.type !== "string") return json({ error: "no event" }, 400);
  try {
    const outcome = await deps.apply(event as Record<string, unknown>);
    return json({ outcome });
  } catch (e) {
    console.error("apply_entitlement_event failed", e instanceof Error ? e.message : e);
    return json({ error: "retry" }, 500); // RevenueCat retries on 5xx
  }
}
