"""Cases for shared/test-vectors/clan-war/groups.json."""

# (id, [(clan, rating, score, contributors, scoreAt ms or None)])
FINALS = [
    ("duel-equal", [("a", 1000, 900, 4, 5000), ("b", 1000, 700, 3, 4000)]),
    ("duel-upset", [("a", 1200, 300, 2, 1000), ("b", 900, 800, 3, 2000)]),
    ("four-equal", [("a", 1000, 1000, 5, 1), ("b", 1000, 800, 5, 1), ("c", 1000, 600, 5, 1), ("d", 1000, 400, 5, 1)]),
    ("four-mixed", [("a", 1300, 500, 3, 10), ("b", 1100, 900, 4, 20), ("c", 1000, 900, 2, 5), ("d", 800, 0, 0, None)]),
    ("three-tie-contributors", [("a", 1000, 600, 6, 100), ("b", 1050, 600, 4, 50), ("c", 950, 200, 1, 10)]),
    ("tie-earlier", [("a", 1000, 500, 3, 9000), ("b", 1000, 500, 3, 7000)]),
    ("all-zero-draw", [("a", 1000, 0, 0, None), ("b", 1040, 0, 0, None), ("c", 980, 0, 0, None)]),
    ("solo-floor", [("a", 10, 0, 0, None), ("b", 1500, 50, 1, 1)]),
]

# (id, {clan: rating}, me)
STAKES = [
    ("duel-equal", {"a": 1000, "b": 1000}, "a"),
    ("four-equal", {"a": 1000, "b": 1000, "c": 1000, "d": 1000}, "a"),
    ("favourite", {"a": 1400, "b": 1000, "c": 1000}, "a"),
    ("underdog", {"a": 900, "b": 1200, "c": 1100, "d": 1000}, "a"),
]

GROUP_SIZES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13]
