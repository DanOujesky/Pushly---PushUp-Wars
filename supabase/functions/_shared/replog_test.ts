import assert from "node:assert/strict";
import { checkAll, type RepLog, validateShape } from "./replog.ts";

// Shared vectors: the same cases the Python reference generated (CLAUDE.md §4.1).
const url = new URL("../../../shared/test-vectors/rep-log/cases.json", import.meta.url);
const { cases } = JSON.parse(await Deno.readTextFile(url)) as {
  cases: { id: string; receivedAtMs: number; log: RepLog; expected: unknown }[];
};

Deno.test("rep-log vectors: checks + server-time session match the reference", async () => {
  assert.ok(cases.length >= 15);
  for (const c of cases) {
    assert.deepEqual(validateShape(c.log), [], `${c.id}: shape`);
    assert.deepEqual(await checkAll(c.log, c.receivedAtMs), c.expected, c.id);
  }
});

Deno.test("shape validation names the broken fields", () => {
  const log = structuredClone(cases[0].log) as Record<string, unknown>;
  log.sessionId = "nope";
  log.outcome = "won";
  (log.reps as Record<string, unknown>[])[0].quality = 140;
  log.rejected = { CHEATING: 1 };
  assert.deepEqual(validateShape(log), ["sessionId", "outcome", "reps", "rejected"]);
  assert.deepEqual(validateShape(null), ["body"]);
});
