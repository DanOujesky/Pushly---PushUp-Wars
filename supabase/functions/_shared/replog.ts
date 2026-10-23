// Rep-log plausibility checks + conversion to server time (doc 06 §4).
// 1:1 port of tools/reference/pushly_ref/rep_log.py; replog_test.ts runs the shared vectors (shared/test-vectors/rep-log).

export const SUPPORTED_SPEC_VERSIONS = new Set([1, 2]);
const MIN_REP_MS = 450, MAX_REP_MS = 8000;
const FAST_REP_MS = 600, FAST_RUN = 3;
const SUSTAINED_REPS = 20, SUSTAINED_RATE = 1.6;
const SET_GAP_MS = 5000, LONG_SET_REPS = 150;
const FUTURE_TOLERANCE_MS = 120_000;
const SESSION_SLACK_MS = 1000;
const REPLAY_MAX = 0.6, MOTION_MAX = 0.5;

export interface Rep {
  i: number;
  tStartMs: number;
  tBottomMs: number;
  tEndMs: number;
  quality: number;
}

export interface RepLog {
  sessionId: string;
  deviceId?: string | null;
  context: { type: "wake" | "battle" | "training"; occurrenceId?: string | null; battleId?: string | null };
  specVersion: number;
  placement?: "side" | "front";
  appVersion: string;
  platform: "ios" | "android";
  timing: {
    monotonicStartMs: number;
    monotonicEndMs: number;
    wallStart: string;
    serverAnchor?: { serverTime: string; monotonicAtAnchorMs: number } | null;
    ringStartedAtMonotonicMs?: number | null;
  };
  outcome: "completed" | "gaveUp" | "expired";
  snoozes?: number;
  sprintStartMs?: number | null;
  sets?: { startMs: number; endMs: number }[];
  reps: Rep[];
  rejected: Record<string, number>;
  suspicion?: { replay?: number; motion?: number; continuity?: number; liveness?: string };
  signature?: string | null;
  [key: string]: unknown;
}

export interface CheckResult {
  hard: string[];
  hold: string[];
  soft: string[];
  anchored: boolean;
  session: Record<string, unknown>;
}

const isoMs = (s: string): number => Date.parse(s);

export function sessionStartMs(log: RepLog): [number, boolean] {
  const t = log.timing;
  if (t.serverAnchor) {
    return [isoMs(t.serverAnchor.serverTime) + (t.monotonicStartMs - t.serverAnchor.monotonicAtAnchorMs), true];
  }
  return [isoMs(t.wallStart), false];
}

export function check(log: RepLog, receivedMs: number): CheckResult {
  const hard: string[] = [], hold: string[] = [], soft: string[] = [];
  const t = log.timing;
  const duration = t.monotonicEndMs - t.monotonicStartMs;
  const reps = log.reps;

  if (!SUPPORTED_SPEC_VERSIONS.has(log.specVersion)) hard.push("spec_version_unsupported");
  let seqOk = duration >= 0;
  reps.forEach((r, k) => {
    if (r.i !== k + 1 || !(r.tStartMs <= r.tBottomMs && r.tBottomMs <= r.tEndMs)) seqOk = false;
    if (k > 0 && r.tStartMs < reps[k - 1].tEndMs) seqOk = false;
  });
  if (!seqOk) hard.push("reps_not_sequential");
  if (reps.some((r) => r.tEndMs - r.tStartMs < MIN_REP_MS || r.tEndMs - r.tStartMs > MAX_REP_MS)) {
    hard.push("rep_duration");
  }
  const ends = reps.map((r) => r.tEndMs);
  for (let j = 0; j < ends.length - SUSTAINED_REPS; j++) {
    if (ends[j + SUSTAINED_REPS] - ends[j] < SUSTAINED_REPS / SUSTAINED_RATE * 1000) {
      hard.push("rate_sustained");
      break;
    }
  }
  if (reps.length && (reps[0].tStartMs < 0 || reps[reps.length - 1].tEndMs > duration + SESSION_SLACK_MS)) {
    hard.push("reps_outside_session");
  }
  const sets = log.sets ?? [];
  if (sets.some((s) => s.endMs < s.startMs || s.endMs > duration + SESSION_SLACK_MS)) hard.push("sets_invalid");

  const [start, anchored] = sessionStartMs(log);
  const ended = start + Math.max(duration, 0);
  if (ended > receivedMs + FUTURE_TOLERANCE_MS) hard.push("clock_in_future");

  let run = 0;
  for (const r of reps) {
    run = r.tEndMs - r.tStartMs < FAST_REP_MS ? run + 1 : 0;
    if (run >= FAST_RUN) {
      soft.push("fast_reps");
      break;
    }
  }
  let bestSet = 0, cur = 0;
  reps.forEach((r, k) => {
    cur = k > 0 && r.tStartMs - reps[k - 1].tEndMs <= SET_GAP_MS ? cur + 1 : 1;
    bestSet = Math.max(bestSet, cur);
  });
  if (bestSet > LONG_SET_REPS) hold.push("long_set");
  const sus = log.suspicion ?? {};
  if ((sus.continuity ?? 0) >= 1) hold.push("feed_discontinuity");
  if ((sus.replay ?? 0) > REPLAY_MAX) soft.push("suspicion_replay");
  if ((sus.motion ?? 0) > MOTION_MAX) soft.push("suspicion_motion");

  const ring = t.ringStartedAtMonotonicMs;
  const session = {
    sessionId: log.sessionId,
    context: log.context.type,
    occurrenceId: log.context.occurrenceId ?? null,
    startedAt: start,
    endedAt: ended,
    ringAt: ring !== null && ring !== undefined ? start + (ring - t.monotonicStartMs) : null,
    outcome: log.outcome,
    snoozes: log.snoozes ?? 0,
    reps: reps.map((r) => ({ tStart: start + r.tStartMs, tEnd: start + r.tEndMs, quality: r.quality })),
    sets: sets.map((s) => ({ start: start + s.startMs, end: start + s.endMs })),
    sprintStart: log.sprintStartMs !== null && log.sprintStartMs !== undefined ? start + log.sprintStartMs : null,
    rejected: log.rejected,
    specVersion: log.specVersion,
    appVersion: log.appVersion,
    platform: log.platform,
    bestSet,
    placement: log.placement === "front" ? "front" : "side",
  };
  return { hard, hold, soft, anchored, session };
}

// ---------------------------------------------------------------------------------------------------------------
// Feature trace (port of pushly_ref/integrity.py trace_codes): every counted rep must show a real dip in the 10 Hz
// elbow trace — ≤ 105° inside the rep and ≥ TRACE_TOP_MIN[specVersion] around its ends (v1 145°, v2 115° — D-062).
// > 20 % of reps without one → hard trace_mismatch.
// ---------------------------------------------------------------------------------------------------------------
const TRACE_WINDOW_MS = 100;
const TRACE_BOTTOM_MAX = 105;
const TRACE_TOP_MIN: Record<number, number> = { 1: 145, 2: 115 };
const TRACE_MISMATCH_SHARE = 0.2;

export async function decodeTrace(trace: string): Promise<number[][] | null> {
  try {
    const bytes = Uint8Array.from(atob(trace), (c) => c.charCodeAt(0));
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
    const data = JSON.parse(await new Response(stream).text());
    return data?.v === 1 && Array.isArray(data.rows) ? data.rows : null;
  } catch {
    return null;
  }
}

export async function traceCodes(log: RepLog): Promise<{ hard: string[]; soft: string[] }> {
  if (!log.reps.length) return { hard: [], soft: [] };
  const trace = typeof log.featureTrace === "string" ? log.featureTrace : null;
  const rows = trace ? await decodeTrace(trace) : null;
  if (!rows || !rows.length) return { hard: [], soft: ["trace_missing"] };
  const topMin = TRACE_TOP_MIN[log.specVersion] ?? TRACE_TOP_MIN[2];
  let bad = 0;
  for (const r of log.reps) {
    const inside = rows.filter((row) => row[0] >= r.tStartMs - TRACE_WINDOW_MS && row[0] <= r.tEndMs + TRACE_WINDOW_MS);
    if (inside.length < 2) {
      bad++;
      continue;
    }
    const elbows = inside.map((row) => row[1]);
    if (!(Math.min(...elbows) <= TRACE_BOTTOM_MAX && Math.max(...elbows) >= topMin)) bad++;
  }
  return { hard: bad > TRACE_MISMATCH_SHARE * log.reps.length ? ["trace_mismatch"] : [], soft: [] };
}

/** All log checks in the reference order (shape-independent part of doc 06 §4). */
export async function checkAll(log: RepLog, receivedMs: number): Promise<CheckResult> {
  const result = check(log, receivedMs);
  const trace = await traceCodes(log);
  return { ...result, hard: [...result.hard, ...trace.hard], soft: [...result.soft, ...trace.soft] };
}

// ---------------------------------------------------------------------------------------------------------------
// Shape validation — mirror of the required parts of shared/contracts/rep-log.schema.json.
// ---------------------------------------------------------------------------------------------------------------
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const REJECT_CODES = new Set([
  "NOT_DEEP_ENOUGH",
  "NO_LOCKOUT",
  "HIPS_SAGGING",
  "HIPS_PIKED",
  "KNEES_DOWN",
  "BODY_NOT_VISIBLE",
  "TOO_FAST",
  "TOO_SLOW",
  "IRREGULAR_MOTION",
  "INTEGRITY",
]);

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isInt = (v: unknown, min = 0): v is number => Number.isInteger(v) && (v as number) >= min;
const optInt = (v: unknown) => v === undefined || v === null || isInt(v);

/** Returns a list of problems (empty = valid). Keeps the error list short and stable for clients. */
export function validateShape(v: unknown): string[] {
  const e: string[] = [];
  if (!isObj(v)) return ["body"];
  if (typeof v.sessionId !== "string" || !UUID.test(v.sessionId)) e.push("sessionId");
  if (v.deviceId !== undefined && v.deviceId !== null && (typeof v.deviceId !== "string" || !UUID.test(v.deviceId))) {
    e.push("deviceId");
  }
  const ctx = v.context;
  if (!isObj(ctx) || !["wake", "battle", "training"].includes(ctx.type as string)) e.push("context.type");
  else if (ctx.occurrenceId !== undefined && ctx.occurrenceId !== null && typeof ctx.occurrenceId !== "string") {
    e.push("context.occurrenceId");
  } else if (
    ctx.battleId !== undefined && ctx.battleId !== null &&
    (typeof ctx.battleId !== "string" || !UUID.test(ctx.battleId))
  ) {
    e.push("context.battleId");
  }
  if (!isInt(v.specVersion, 1)) e.push("specVersion");
  if (typeof v.appVersion !== "string" || v.appVersion.length > 40) e.push("appVersion");
  if (v.platform !== "ios" && v.platform !== "android") e.push("platform");
  const t = v.timing;
  if (!isObj(t) || !isInt(t.monotonicStartMs) || !isInt(t.monotonicEndMs)) e.push("timing");
  else {
    if (typeof t.wallStart !== "string" || Number.isNaN(Date.parse(t.wallStart))) e.push("timing.wallStart");
    const a = t.serverAnchor;
    if (
      a !== undefined && a !== null &&
      (!isObj(a) || typeof a.serverTime !== "string" || Number.isNaN(Date.parse(a.serverTime)) ||
        !isInt(a.monotonicAtAnchorMs))
    ) e.push("timing.serverAnchor");
    if (!optInt(t.ringStartedAtMonotonicMs)) e.push("timing.ringStartedAtMonotonicMs");
  }
  if (!["completed", "gaveUp", "expired"].includes(v.outcome as string)) e.push("outcome");
  if (v.snoozes !== undefined && !(isInt(v.snoozes) && (v.snoozes as number) <= 20)) e.push("snoozes");
  if (!optInt(v.sprintStartMs)) e.push("sprintStartMs");
  if (v.sets !== undefined) {
    if (
      !Array.isArray(v.sets) || v.sets.length > 20 ||
      v.sets.some((s) => !isObj(s) || !isInt(s.startMs) || !isInt(s.endMs))
    ) {
      e.push("sets");
    }
  }
  if (
    !Array.isArray(v.reps) || v.reps.length > 2000 ||
    v.reps.some((r) =>
      !isObj(r) || !isInt(r.i, 1) || !isInt(r.tStartMs) || !isInt(r.tBottomMs) || !isInt(r.tEndMs) ||
      !isInt(r.quality) || (r.quality as number) > 100
    )
  ) e.push("reps");
  if (!isObj(v.rejected) || Object.entries(v.rejected).some(([k, n]) => !REJECT_CODES.has(k) || !isInt(n))) {
    e.push("rejected");
  }
  if (v.suspicion !== undefined && v.suspicion !== null) {
    const s = v.suspicion;
    const unit = (x: unknown) => x === undefined || (typeof x === "number" && x >= 0 && x <= 1);
    if (!isObj(s) || !unit(s.replay) || !unit(s.motion) || !unit(s.continuity)) e.push("suspicion");
  }
  if (v.signature !== undefined && v.signature !== null && typeof v.signature !== "string") e.push("signature");
  if (v.placement !== undefined && v.placement !== null && v.placement !== "side" && v.placement !== "front") {
    e.push("placement");
  }
  return e;
}
