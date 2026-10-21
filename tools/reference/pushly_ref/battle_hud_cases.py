"""Hand-labelled HUD cases. build_vectors.py asserts them and writes shared/test-vectors/battles/hud.json."""

BO3 = [
    ("before-go", -2500, {"round": 0, "phase": "countdown", "msLeft": 2500}),
    ("go", 0, {"round": 0, "phase": "set", "msLeft": 90000}),
    ("round-1-mid", 30000, {"round": 0, "phase": "set", "msLeft": 60000}),
    ("round-1-last-ms", 89999, {"round": 0, "phase": "set", "msLeft": 1}),
    ("rest-1-starts", 90000, {"round": 0, "phase": "rest", "msLeft": 45000}),
    ("rest-1-end", 134999, {"round": 0, "phase": "rest", "msLeft": 1}),
    ("round-2-start", 135000, {"round": 1, "phase": "set", "msLeft": 90000}),
    ("rest-2", 240000, {"round": 1, "phase": "rest", "msLeft": 30000}),
    ("round-3-start", 270000, {"round": 2, "phase": "set", "msLeft": 90000}),
    ("round-3-last-ms", 359999, {"round": 2, "phase": "set", "msLeft": 1}),
    ("over", 360000, {"round": 2, "phase": "over", "msLeft": 0}),
    ("long-over", 999999, {"round": 2, "phase": "over", "msLeft": 0}),
]

CLINCHED = [
    ("two-wins", [12, 10], [8, 9], True),
    ("tie-round", [12, 9], [8, 9], False),
    ("lost-one", [12, 7], [8, 9], False),
    ("only-one-round", [12], [8], False),
    ("raw-is-upper-bound", [10, 10], [10, 3], False),
]

TURNS = [
    ("nobody-yet", 4000, None, None, {"turn": "anyone", "msLeft": None}),
    ("i-started", 4000, 3000, None, {"turn": "them", "msLeft": 4000}),
    ("they-started", 4000, None, 3500, {"turn": "me", "msLeft": 4500}),
    ("my-turn", 10000, 6000, 8000, {"turn": "me", "msLeft": 3000}),
    ("their-turn", 10000, 9000, 8000, {"turn": "them", "msLeft": 4000}),
    ("i-am-overdue", 15000, 6000, 8000, {"turn": "me", "msLeft": -2000}),
    ("same-ms-goes-to-me", 9000, 8000, 8000, {"turn": "me", "msLeft": 4000}),
]
