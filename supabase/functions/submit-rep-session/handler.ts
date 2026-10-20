import { ErrorCode, errorResponse, json, preflight } from "../_shared/http.ts";
import { checkAll, type RepLog, validateShape } from "../_shared/replog.ts";

/**
 * POST /submit-rep-session  (doc 06 §3–4, doc 12 §1)
 * Validates an uploaded rep log, converts it to server time and applies it in one DB transaction
 * (`apply_validated_session`). Idempotent by sessionId. Failing plausibility checks never reject the upload: the
 * session is stored with verified = false and flags (it still counts for personal stats).
 * Signature / attestation verification arrives with P4-02; until then `integrity` is reported as "not_checked".
 */
export interface Deps {
  now(): number;
  getUser(authorization: string): Promise<{ id: string } | null>;
  apply(payload: Record<string, unknown>): Promise<ApplyResult>;
}

export type ApplyResult =
  | { ok: true; result: unknown }
  | { ok: false; code: "duplicate_log" | "session_conflict" | "unknown_user" | "internal"; message: string };

export async function handler(req: Request, deps: Deps): Promise<Response> {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return errorResponse(ErrorCode.VALIDATION_FAILED, "method not allowed");
  const auth = req.headers.get("Authorization") ?? "";
  const user = auth.startsWith("Bearer ") ? await deps.getUser(auth) : null;
  if (!user) return errorResponse(ErrorCode.UNAUTHENTICATED, "sign in required");

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse(ErrorCode.VALIDATION_FAILED, "invalid JSON");
  }
  const problems = validateShape(body);
  if (problems.length) return errorResponse(ErrorCode.VALIDATION_FAILED, "invalid rep log", { fields: problems });
  const log = body as RepLog;

  const receivedMs = deps.now();
  const result = await checkAll(log, receivedMs);
  const verified = result.hard.length === 0 && result.hold.length === 0;
  const flags = [
    ...result.hard.map((type) => ({ type, severity: "hard", details: {} })),
    ...[...result.hold, ...result.soft].map((type) => ({ type, severity: "soft", details: {} })),
  ];
  const applied = await deps.apply({
    userId: user.id,
    deviceId: log.deviceId ?? null,
    receivedAt: new Date(receivedMs).toISOString(),
    verified,
    verification: {
      checks: { hard: result.hard, hold: result.hold, soft: result.soft },
      anchored: result.anchored,
      integrity: "not_checked",
      ...(result.hold.length ? { hold: result.hold[0] } : {}),
    },
    flags,
    log,
    signature: log.signature ?? null,
    session: result.session,
  });
  if (applied.ok) return json(applied.result);
  switch (applied.code) {
    case "duplicate_log":
      return errorResponse(ErrorCode.CONFLICT, "this rep log was already submitted under another session");
    case "session_conflict":
      return errorResponse(ErrorCode.CONFLICT, "sessionId belongs to another user");
    case "unknown_user":
      return errorResponse(ErrorCode.NOT_FOUND, "profile not found");
    default:
      return errorResponse(ErrorCode.INTERNAL, "could not store the session");
  }
}
