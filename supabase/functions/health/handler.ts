import { ErrorCode, errorResponse, json, preflight } from "../_shared/http.ts";

/**
 * GET or POST /health → { ok: true, serverMs }  (POST: the Supabase client SDKs invoke functions with POST)
 * Used for uptime checks and as the template every new function follows (handler separated from Deno.serve
 * so it can be unit-tested). `serverMs` also serves early clock-offset experiments (doc 07 §4.3).
 */
export function handler(req: Request, now: () => number = Date.now): Response {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "GET" && req.method !== "POST") {
    return errorResponse(ErrorCode.VALIDATION_FAILED, "method not allowed", { method: req.method });
  }
  return json({ ok: true, serverMs: now() });
}
