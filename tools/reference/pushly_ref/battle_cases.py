"""Hand-labelled battle cases (doc 07 §2). build_vectors.py asserts every label against battle.decide and writes
shared/test-vectors/battles/results.json."""


def reps(times: list[int], q: int = 80, rnd: int = 0) -> list[dict]:
    return [{"t": t, "q": q, "round": rnd} for t in times]


def every(n: int, start: int, step: int, q: int = 80, rnd: int = 0) -> list[dict]:
    return reps([start + i * step for i in range(n)], q, rnd)


CASES = [
    # id, mode, variant, a, b, expected winner, expected reason
    ("max-more-reps", "max_reps", {"durationS": 60}, every(30, 1000, 1500), every(25, 1000, 1500), "a", "reps"),
    ("max-after-whistle-ignored", "max_reps", {"durationS": 30},
     every(20, 1000, 1400) + reps([31_000, 32_000]), every(21, 1000, 1400), "b", "reps"),
    ("max-tie-quality", "max_reps", {"durationS": 60}, every(20, 1000, 2000, q=90), every(20, 1000, 2000, q=85), "a", "reps"),
    ("max-tie-earlier-last-rep", "max_reps", {"durationS": 60}, every(20, 1000, 2000), every(20, 900, 2000), "b", "reps"),
    ("max-full-tie", "max_reps", {"durationS": 60}, every(10, 1000, 2000), every(10, 1000, 2000), None, "draw"),
    ("max-nobody", "max_reps", {"durationS": 60}, [], [], None, "draw"),
    ("speed-first-to-20", "speed", {"targetReps": 20}, every(20, 800, 1100), every(25, 800, 1000), "b", "target"),
    ("speed-only-one-finishes", "speed", {"targetReps": 10}, every(10, 800, 1500), every(9, 800, 1000), "a", "target"),
    ("speed-nobody-finishes", "speed", {"targetReps": 30}, every(12, 1000, 9000), every(12, 1000, 8000), "b", "reps"),
    ("endurance-pause-ends-set", "endurance", {}, every(10, 1000, 2000) + every(20, 25_000, 2000),
     every(15, 1000, 2500), "b", "reps"),
    ("endurance-tie-earlier-finish", "endurance", {}, every(15, 1000, 2000), every(15, 1000, 1900), "b", "reps"),
    ("bo3-two-straight", "best_of_3", {}, every(15, 0, 1500, rnd=0) + every(12, 60_000, 1500, rnd=1),
     every(10, 0, 1500, rnd=0) + every(11, 60_000, 1500, rnd=1), "a", "rounds"),
    ("bo3-comeback", "best_of_3", {}, every(15, 0, 1500, rnd=0) + every(10, 60_000, 1500, rnd=1) + every(9, 120_000, 1500, rnd=2),
     every(14, 0, 1500, rnd=0) + every(12, 60_000, 1500, rnd=1) + every(10, 120_000, 1500, rnd=2), "b", "rounds"),
    ("bo3-pause-cuts-set", "best_of_3", {}, every(5, 0, 1500, rnd=0) + every(10, 10_000, 1500, rnd=0) + every(8, 60_000, 1500, rnd=1),
     every(8, 0, 1500, rnd=0) + every(7, 60_000, 1500, rnd=1) + every(9, 120_000, 1500, rnd=2), "b", "rounds"),
    ("bo3-tied-rounds-total-reps", "best_of_3", {}, every(10, 0, 1500, rnd=0) + every(10, 60_000, 1500, rnd=1) + every(12, 120_000, 1500, rnd=2),
     every(10, 0, 1500, rnd=0) + every(10, 60_000, 1500, rnd=1) + every(12, 120_000, 1500, rnd=2), None, "draw"),
    ("turns-b-misses", "turns", {}, reps([1000, 5000, 9000]), reps([3000, 7000]), "a", "turn_missed"),
    ("turns-a-too-slow", "turns", {}, reps([1000, 9500]), reps([3000]), "b", "turn_missed"),
    ("turns-latency-grace", "turns", {"latencyMs": 400}, reps([1000, 8300]), reps([3000, 13_800]), "a", "turn_missed"),
    ("turns-extra-rep-ignored", "turns", {}, reps([1000, 1500, 6000]), reps([3000]), "a", "turn_missed"),
    ("turns-nobody", "turns", {}, [], [], None, "draw"),
]
