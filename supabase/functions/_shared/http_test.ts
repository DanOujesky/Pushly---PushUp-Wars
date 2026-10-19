import assert from "node:assert/strict";
import { ErrorCode, errorResponse } from "./http.ts";

Deno.test("retryable flag is true only for RATE_LIMITED and INTERNAL", async () => {
  for (const code of Object.values(ErrorCode)) {
    const body = await errorResponse(code, "x").json();
    const expected = code === "RATE_LIMITED" || code === "INTERNAL";
    assert.equal(body.error.retryable, expected, code);
    assert.deepEqual(Object.keys(body.error).sort(), ["code", "details", "message", "retryable"]);
  }
});

Deno.test("status codes map as documented", () => {
  assert.equal(errorResponse(ErrorCode.UNAUTHENTICATED, "x").status, 401);
  assert.equal(errorResponse(ErrorCode.UPGRADE_REQUIRED, "x").status, 426);
  assert.equal(errorResponse(ErrorCode.RATE_LIMITED, "x").status, 429);
});
