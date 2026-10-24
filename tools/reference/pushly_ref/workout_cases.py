"""Hand-written workout runner cases. build_vectors.py runs them through workout.py and writes
shared/test-vectors/workouts/runner.json (events, results and a final HUD snapshot per case)."""


def reps(*targets, rest=10):
    return [{"kind": "reps", "target": t, "restS": rest} for t in targets]


def ops(*pairs):
    return [{"op": op, "t": t} for op, t in pairs]


def rep_run(start, n, every=1000):
    return [("rep", start + i * every) for i in range(n)]


W_REPS = {"id": "w-reps", "name": "Reps", "sets": reps(3, 2, rest=10)}
W_AMRAP = {"id": "w-amrap", "name": "Amrap", "sets": [{"kind": "amrap", "target": 0, "restS": 30},
                                                      {"kind": "amrap", "target": 0, "restS": 0}]}
W_TIMED = {"id": "w-timed", "name": "Timed", "sets": [{"kind": "timed", "target": 20, "restS": 10},
                                                      {"kind": "timed", "target": 20, "restS": 0}]}
W_EMOM = {"id": "w-emom", "name": "Emom", "everyS": 60, "sets": reps(5, 5, 5, rest=0)}
W_MIX = {"id": "w-mix", "name": "Mix", "sets": [{"kind": "reps", "target": 2, "restS": 0},
                                                {"kind": "timed", "target": 10, "restS": 5},
                                                {"kind": "amrap", "target": 0, "restS": 0}]}

RUNNER = [
    ("reps-complete", W_REPS, ops(("start", 0), *rep_run(1000, 3), ("tick", 12999), ("tick", 13000),
                                  *rep_run(14000, 2)), 20000),
    ("reps-rest-reps-count-to-total", W_REPS, ops(("start", 0), *rep_run(1000, 3), ("rep", 5000), ("rep", 6000),
                                                  ("tick", 13500)), 13500),
    ("reps-end-early", W_REPS, ops(("start", 0), ("rep", 1000), ("endSet", 3000), ("skipRest", 4000),
                                   *rep_run(5000, 2)), 7000),
    ("reps-finish-midway", W_REPS, ops(("start", 0), ("rep", 1000), ("finish", 2000), ("rep", 3000)), 3000),
    ("reps-before-start-ignored", W_REPS, ops(("rep", 0), ("start", 500), ("tick", 600)), 600),
    ("amrap-idle-ends", W_AMRAP, ops(("start", 0), ("tick", 10000), *rep_run(10000, 4, 1500), ("tick", 20499),
                                     ("tick", 20500), ("tick", 50499)), 50499),
    ("amrap-no-reps-waits", W_AMRAP, ops(("start", 0), ("tick", 60000)), 60000),
    ("amrap-manual", W_AMRAP, ops(("start", 0), ("rep", 1000), ("endSet", 2000), ("skipRest", 2500),
                                  ("rep", 3000), ("tick", 9000)), 9000),
    ("timed-sets", W_TIMED, ops(("start", 0), *rep_run(1000, 5, 3000), ("tick", 20000), ("tick", 29999),
                                ("tick", 30000), ("tick", 50000)), 50000),
    ("timed-empty-not-completed", W_TIMED, ops(("start", 0), ("tick", 25000)), 25000),
    ("emom-on-the-minute", W_EMOM, ops(("start", 0), *rep_run(1000, 5, 2000), ("tick", 59999), ("tick", 60000),
                                       *rep_run(61000, 3), ("tick", 120000), *rep_run(121000, 5)), 126000),
    ("emom-catch-up-in-one-tick", W_EMOM, ops(("start", 0), ("tick", 200000)), 200000),
    ("mix-zero-rest-runs-on", W_MIX, ops(("start", 0), ("rep", 500), ("rep", 900), ("tick", 10900),
                                         ("tick", 15900), ("rep", 16000), ("tick", 22000)), 22000),
]

VALIDATION = [
    ("ok", {"name": "Mine", "sets": reps(10)}, []),
    ("blank-name", {"name": "  ", "sets": reps(10)}, ["name"]),
    ("no-sets", {"name": "Mine", "sets": []}, ["sets"]),
    ("too-many-sets", {"name": "Mine", "sets": reps(*([5] * 21))}, ["sets"]),
    ("reps-zero", {"name": "Mine", "sets": reps(0)}, ["sets[0].target"]),
    ("reps-too-many", {"name": "Mine", "sets": reps(201)}, ["sets[0].target"]),
    ("timed-too-short", {"name": "Mine", "sets": [{"kind": "timed", "target": 4, "restS": 0}]}, ["sets[0].target"]),
    ("amrap-with-target", {"name": "Mine", "sets": [{"kind": "amrap", "target": 5, "restS": 0}]}, ["sets[0].target"]),
    ("rest-too-long", {"name": "Mine", "sets": reps(5, rest=601)}, ["sets[0].restS"]),
    ("emom-bad-interval", {"name": "Mine", "everyS": 10, "sets": reps(5)}, ["everyS"]),
    ("emom-needs-reps", {"name": "Mine", "everyS": 60, "sets": [{"kind": "timed", "target": 20, "restS": 0}]},
     ["sets[0].kind"]),
]
