import { ErrorCode, errorResponse, json, preflight } from "../_shared/http.ts";
import { checkAll, type RepLog, validateShape } from "../_shared/replog.ts";
import { verifyP256 } from "../_shared/signature.ts";

/**
 * POST /submit-rep-session  (doc 06 §3–4, doc 12 §1)
 * Validates an uploaded rep log, converts it to server time and applies it in one DB transaction
 * (`apply_validated_session`). Idempotent by sessionId. Failing plausibility checks never reject the upload: the
 * session is stored with verified = false and flags (it still counts for personal stats).
 *
 * Body: the signed envelope `{ log: "<rep log JSON>", signature, deviceId }` — ECDSA P-256 over the exact log bytes
 * with the device key registered by `register_device` (doc 06 §3, D-047) — or, from older apps, the bare rep log
 * (accepted, soft flag `unsigned_log`). A bad signature or a foreign / unknown device is a hard failure.
 */
export interface Deps {
  now(): number;
  getUser(authorization: string): Promise<{ id: string } | null>;
  getDevice(id: string): Promise<{ userId: string; publicKey: string | null; revokedAt: string | null } | null>;
  apply(payload: Record<string, unknown>): Promise<ApplyResult>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
  // Signed envelope or bare (legacy) log.
  let logBody: unknown = body;
  let integrity = "unsigned";
  let deviceId: string | null = null;
  const integrityHard: string[] = [];
  const envelope = typeof body === "object" && body !== null && typeof (body as { log?: unknown }).log === "string"
    ? body as { log: string; signature?: unknown; deviceId?: unknown }
    : null;
  if (envelope) {
    try {
      logBody = JSON.parse(envelope.log);
    } catch {
      return errorResponse(ErrorCode.VALIDATION_FAILED, "invalid rep log", { fields: ["log"] });
    }
    const id = typeof envelope.deviceId === "string" && UUID.test(envelope.deviceId) ? envelope.deviceId : null;
    const device = id ? await deps.getDevice(id) : null;
    if (!device || device.userId !== user.id || !device.publicKey) {
      integrity = "device_unknown";
      integrityHard.push("device_unknown");
    } else if (
      typeof envelope.signature !== "string" ||
      !(await verifyP256(device.publicKey, new TextEncoder().encode(envelope.log), envelope.signature))
    ) {
      integrity = "invalid";
      integrityHard.push("signature_invalid");
    } else {
      integrity = "signed";
      deviceId = id;
    }
  }
  const problems = validateShape(logBody);
  if (problems.length) return errorResponse(ErrorCode.VALIDATION_FAILED, "invalid rep log", { fields: problems });
  const log = logBody as RepLog;

  const receivedMs = deps.now();
  const checked = await checkAll(log, receivedMs);
  const result = {
    ...checked,
    hard: [...integrityHard, ...checked.hard],
    soft: integrity === "unsigned" ? [...checked.soft, "unsigned_log"] : checked.soft,
  };
  const verified = result.hard.length === 0 && result.hold.length === 0;
  const flags = [
    ...result.hard.map((type) => ({ type, severity: "hard", details: {} })),
    ...[...result.hold, ...result.soft].map((type) => ({ type, severity: "soft", details: {} })),
  ];
  const applied = await deps.apply({
    userId: user.id,
    deviceId,
    receivedAt: new Date(receivedMs).toISOString(),
    verified,
    verification: {
      checks: { hard: result.hard, hold: result.hold, soft: result.soft },
      anchored: result.anchored,
      integrity,
      ...(result.hold.length ? { hold: result.hold[0] } : {}),
    },
    flags,
    log,
    signature: envelope && typeof envelope.signature === "string" ? envelope.signature : null,
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
