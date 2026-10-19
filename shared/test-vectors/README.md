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

## alarm-occurrences/*.json
```jsonc
{ "id": "prague-spring-forward",
  "timeZone": "Europe/Prague",
  "from": "2027-03-27T20:00:00Z",
  "horizonDays": 3,
  "schedule": { /* AlarmSchedule */ },
  "expected": [ { "occurrenceId": "…:2027-03-28", "instant": "2027-03-28T01:00:00Z" } ] }
```

## trophies/*.json, clan-war/*.json
Input state + action → expected output, exact numeric equality (integers only; no floats in trophy math).
