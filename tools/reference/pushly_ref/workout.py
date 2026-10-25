"""Workout runner (doc 05 §Workouts, D-069): turns a workout plan + push-ups counted by the rep engine into sets,
rest periods and a result. Pure state machine over monotonic milliseconds; iOS and Android replay
shared/test-vectors/workouts/runner.json against their own ports.

Workout  {id, name, everyS?: int, sets: [{kind: "reps"|"amrap"|"timed", target: int, restS: int}]}
  reps   — set ends when `target` push-ups are done (completed) or when the user ends it (completed iff reached).
  amrap  — as many as possible: ends only when the user taps End set (or finishes the workout). target is 0.
           completed iff ≥ 1 rep.
  timed  — ends `target` seconds after it started; completed iff ≥ 1 rep.
  everyS — EMOM: every set starts on the clock, `everyS` seconds after the previous one. A reps set that reaches its
           target early rests until the next start; one that isn't finished in time ends (not completed) and the next
           set starts right away. restS is ignored.
Push-ups during rest count to the workout total, never to a set. Every push-up counts for the day (clan wars etc.)
because the whole workout is one training session.
"""

from __future__ import annotations

from dataclasses import dataclass, field

MAX_SETS = 20
MAX_TARGET_REPS = 200
MAX_TIMED_S = 600
MAX_REST_S = 600
EVERY_S_RANGE = (20, 300)


def validate(w: dict) -> list[str]:
    """Problems with a user-made workout (empty = valid). The editor refuses to save until this is empty."""
    errs = []
    if not str(w.get("name", "")).strip():
        errs.append("name")
    sets = w.get("sets") or []
    if not 1 <= len(sets) <= MAX_SETS:
        errs.append("sets")
    every = w.get("everyS")
    if every is not None and not EVERY_S_RANGE[0] <= every <= EVERY_S_RANGE[1]:
        errs.append("everyS")
    for i, s in enumerate(sets):
        k, t, r = s.get("kind"), s.get("target", 0), s.get("restS", 0)
        if k == "reps" and not 1 <= t <= MAX_TARGET_REPS:
            errs.append(f"sets[{i}].target")
        elif k == "timed" and not 5 <= t <= MAX_TIMED_S:
            errs.append(f"sets[{i}].target")
        elif k == "amrap" and t != 0:
            errs.append(f"sets[{i}].target")
        elif k not in ("reps", "amrap", "timed"):
            errs.append(f"sets[{i}].kind")
        if every is not None and k != "reps":
            errs.append(f"sets[{i}].kind")
        if not 0 <= r <= MAX_REST_S:
            errs.append(f"sets[{i}].restS")
    return errs


def planned_reps(w: dict) -> int | None:
    """Total push-ups the plan asks for, or None when a set has no fixed count (amrap / timed)."""
    total = 0
    for s in w["sets"]:
        if s["kind"] != "reps":
            return None
        total += s["target"]
    return total


@dataclass
class Runner:
    workout: dict
    phase: str = "ready"            # ready | set | rest | done
    index: int = 0                  # current set (in rest: the set that comes next)
    set_reps: int = 0
    set_start: int = 0
    rest_end: int = 0
    total: int = 0
    results: list[dict] = field(default_factory=list)
    events: list[dict] = field(default_factory=list)

    @property
    def sets(self) -> list[dict]:
        return self.workout["sets"]

    @property
    def every_ms(self) -> int | None:
        e = self.workout.get("everyS")
        return e * 1000 if e else None

    # --- inputs -------------------------------------------------------------------------------------------------
    def start(self, t: int) -> None:
        if self.phase == "ready":
            self._start_set(0, t)

    def rep(self, t: int) -> None:
        self.tick(t)
        if self.phase == "ready" or self.phase == "done":
            return
        self.total += 1
        if self.phase != "set":
            return
        self.set_reps += 1
        s = self.sets[self.index]
        if s["kind"] == "reps" and self.set_reps >= s["target"]:
            self._end_set(t)

    def tick(self, t: int) -> None:
        # loop: one tick may cross several boundaries (e.g. an EMOM minute ends while the app was paused)
        while True:
            if self.phase == "set":
                d = self._set_deadline()
                if d is None or t < d:
                    return
                self._end_set(d)
            elif self.phase == "rest":
                if t < self.rest_end:
                    return
                self._start_set(self.index, self.rest_end)
            else:
                return

    def end_set(self, t: int) -> None:
        self.tick(t)
        if self.phase == "set":
            self._end_set(t)

    def skip_rest(self, t: int) -> None:
        self.tick(t)
        if self.phase == "rest":
            self._start_set(self.index, t)

    def finish(self, t: int) -> None:
        """User stops the whole workout early: a running set is recorded as it is, the rest are skipped."""
        self.tick(t)
        if self.phase == "set":
            self._record(t)
        if self.phase != "done":
            self.phase = "done"
            self.events.append({"type": "done", "t": t})

    # --- state for the HUD ---------------------------------------------------------------------------------------
    def snapshot(self, t: int) -> dict:
        s = self.sets[min(self.index, len(self.sets) - 1)]
        left = None
        if self.phase == "set":
            d = self._set_deadline()
            left = None if d is None or s["kind"] == "amrap" else max(d - t, 0)
        elif self.phase == "rest":
            left = max(self.rest_end - t, 0)
        return {"phase": self.phase, "index": self.index, "setReps": self.set_reps, "total": self.total,
                "msLeft": left}

    # --- internals -----------------------------------------------------------------------------------------------
    def _set_deadline(self) -> int | None:
        s = self.sets[self.index]
        if self.every_ms is not None:
            return self.set_start + self.every_ms
        if s["kind"] == "timed":
            return self.set_start + s["target"] * 1000
        return None

    def _start_set(self, i: int, t: int) -> None:
        self.phase = "set"
        self.index = i
        self.set_reps = 0
        self.set_start = t
        self.events.append({"type": "setStarted", "set": i, "t": t})

    def _record(self, t: int) -> None:
        s = self.sets[self.index]
        done = self.set_reps >= s["target"] if s["kind"] == "reps" else self.set_reps >= 1
        self.results.append({"reps": self.set_reps, "target": s["target"], "completed": done})
        self.events.append({"type": "setEnded", "set": self.index, "reps": self.set_reps, "completed": done, "t": t})

    def _end_set(self, t: int) -> None:
        self._record(t)
        nxt = self.index + 1
        if nxt >= len(self.sets):
            self.phase = "done"
            self.events.append({"type": "done", "t": t})
            return
        if self.every_ms is not None:
            rest_end = self.set_start + self.every_ms
        else:
            rest_end = t + self.sets[self.index]["restS"] * 1000
        if rest_end <= t:
            self._start_set(nxt, t)
            return
        self.phase = "rest"
        self.index = nxt
        self.rest_end = rest_end
        self.events.append({"type": "restStarted", "next": nxt, "until": rest_end, "t": t})


def run(workout: dict, steps: list[dict]) -> Runner:
    r = Runner(workout)
    for s in steps:
        getattr(r, {"start": "start", "rep": "rep", "tick": "tick", "endSet": "end_set", "skipRest": "skip_rest",
                    "finish": "finish"}[s["op"]])(s["t"])
    return r
