# Test vectors

Golden data that **both** platform implementations must pass in CI. Never edit an `expected` block to make a failing test pass without a human-reviewed decisions-log entry.

```
test-vectors/
├── pushup/            # RepEngine vectors (landmark sequences)
├── alarm-occurrences/ # occurrence computation (doc 04 §4)
├── trophies/          # trophy & MMR math (doc 08)
└── clan-war/          # clan war scoring & caps (doc 09)
```

## pushup/*.json
```jsonc
{
  "id": "side-left-normal-012",
  "specVersion": 1,
  "meta": {
    "placement": "side",           // side | front
    "camera": "front",             // front | rear
    "device": "iPhone 13",
    "fps": 30,
    "lighting": "lamp",
    "tags": ["normal", "male", "loose-clothing"],
    "humanCount": 12,
    "labeller": "dan",
    "notes": ""
  },
  "frames": [
    { "t": 0, "lm": [[0.51, 0.42, -0.1, 0.98, 0.99], /* ×33: x,y,z,visibility,presence */],
              "w":  [[0.01, -0.45, -0.05], /* ×33 world xyz metres */] }
  ],
  "expected": {
    "counted": 12,
    "rejected": { "NOT_DEEP_ENOUGH": 1 },     // optional, exact-match only if present
    "toleranceCounted": 0                      // 0 for cheat vectors; ≤ 1 allowed only for tags ["edge"]
  }
}
```
Cheat vectors use `tags: ["cheat", "<type>"]` and `expected.counted: 0`, `toleranceCounted: 0`.

## Generated vectors (alarm, trophies, clan war)
These are **generated** by the executable reference in `tools/reference` (`python3 tools/reference/build_vectors.py`, CI runs it with `--check`). To change a rule: change the doc, the reference code and its hand-written tests (`tools/reference/test_reference.py`), regenerate, add a decisions-log entry. Never hand-edit these JSON files.

### alarm-occurrences/*.json (doc 04 §4)
```jsonc
{ "id": "prague-spring-forward-gap-0230",
  "timeZone": "Europe/Prague",
  "from": "2027-03-27T12:00:00Z",           // fromInstant (UTC)
  "horizonDays": 2,                         // local dates [today, today + horizonDays] inclusive
  "schedules": [ /* AlarmSchedule objects (doc 04 §2) */ ],
  "expected": {
    "occurrences": [ { "occurrenceId": "<alarmId>:2027-03-28", "alarmId": "...", "localDate": "2027-03-28",
                       "instant": "2027-03-28T01:00:00Z", "countsForChallenge": true } ],   // sorted by instant, then alarmId
    "challengeByLocalDate": { "2027-03-28": "<occurrenceId>" | null }                          // doc 04 §1
  } }
```

### alarm-validation/cases.json (doc 04 §2)
`{ "today": "2026-10-19", "cases": [ { "id", "schedule", "expectedErrors": ["mode.targetReps", ...] } ] }` — error codes are part of the contract (clients map them to UI messages); compare as sets.

### trophies/*.json (doc 08)
- `win-loss-table.json` — `{me, opp, winGain, lossCost}`
- `sequences.json` — start state `{trophies, floor, placement_left, win_streak}` + steps `{opp, outcome, delta, after}`
- `leagues.json` — `{trophies, league, tier}`; `season-reset.json` — `{before, after}`; `wake-points.json` — `{mode, finalTargetReps, avgQuality, snoozesUsed, points}`

### clan-war/*.json (doc 09 §3)
- `day-totals.json` — `{rawRepsDay, lowTrust, counted}`
- `session-splits.json` — sessions within one day `{repsTodayBefore, newReps, counted}` + `dayTotalCounted`

All numbers are integers; compare with exact equality.
