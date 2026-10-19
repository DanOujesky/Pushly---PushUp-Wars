// Shared HTTP helpers for all Edge Functions (doc 12).
// Error format: { "error": { "code", "message", "retryable", "details" } }

export const ErrorCode = {
  UNAUTHENTICATED: "UNAUTHENTICATED",
  FORBIDDEN: "FORBIDDEN",
  VALIDATION_FAILED: "VALIDATION_FAILED",
  NOT_FOUND: "NOT_FOUND",
  CONFLICT: "CONFLICT",
  RATE_LIMITED: "RATE_LIMITED",
  INTEGRITY_FAILED: "INTEGRITY_FAILED",
  UPGRADE_REQUIRED: "UPGRADE_REQUIRED",
  INTERNAL: "INTERNAL",
} as const;

export type ErrorCode = typeof ErrorCode[keyof typeof ErrorCode];

const STATUS: Record<ErrorCode, number> = {
  UNAUTHENTICATED: 401,
  FORBIDDEN: 403,
  VALIDATION_FAILED: 422,
  NOT_FOUND: 404,
  CONFLICT: 409,
  RATE_LIMITED: 429,
  INTEGRITY_FAILED: 403,
  UPGRADE_REQUIRED: 426,
  INTERNAL: 500,
};

/** Only these codes may be retried by the client outbox (doc 03 §5). */
const RETRYABLE: ReadonlySet<ErrorCode> = new Set([ErrorCode.RATE_LIMITED, ErrorCode.INTERNAL]);

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function json(body: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders, ...extraHeaders },
  });
}

export function errorResponse(
  code: ErrorCode,
  message: string,
  details: Record<string, unknown> = {},
): Response {
  return json({ error: { code, message, retryable: RETRYABLE.has(code), details } }, STATUS[code]);
}

export function preflight(req: Request): Response | null {
  return req.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}
