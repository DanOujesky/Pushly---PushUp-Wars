# Recording real push-up vectors (roadmap P3-04 / P3-05)

Real recordings make the rep engine honest: the 25 synthetic vectors come from a body model, real people do not.
Only **landmarks** (33 body points per frame) are recorded — never video or photos (D-041, CLAUDE.md §4.3).

## On the phone (debug build)
1. Wake tab → **Pose recorder (debug)** (below "Free training"; only in debug builds).
2. Place the phone (side view is the default, 1.5–2.5 m away, lens near the floor), get into frame, do the set.
   The live counter is the engine's opinion — ignore it, do what the scenario says.
3. Tap **Stop & label**:
   - **Real push-ups** = what a strict human judge would count (full depth, full lockout, straight body).
   - Placement side / front; tags (pick all that apply, `cheat` for anything that must count 0, `edge` when even a
     human would hesitate on one rep — allows ±1).
   - Notes: lighting, clothing, who (first name or initials is enough), anything unusual.
4. **Save vector** → **Share** → send the `real-….json` file to yourself (email, Drive, AirDrop…).

## On the computer
```bash
python3 tools/pose-recorder/import.py ~/Downloads/real-side-12-20261020T190000Z.json
```
- Prints the human count vs the engine's count. If they agree → the file lands in `shared/test-vectors/pushup/` as
  `real-….json.gz`; commit it.
- If they disagree, the import stops. Either the engine needs tuning (tell Claude — attach the file), or keep it as a
  tracked gap: `--known-gap "dim light, elbows hidden by hoodie"`.

## What to record (target ≥ 200 vectors, ≥ 30 people before Phase 3 is closed)
| Set | How | Tags |
|---|---|---|
| Normal sets | 5–15 good reps, side view, left and right side | `normal` |
| Front view | phone on the floor in front of the head | `normal` (placement front) |
| Speed | very slow (3–4 s per rep), fast but full | `slow` / `fast` |
| Fatigue | last reps of a max set (shaky, shallow) | `normal`, `edge` if unsure |
| Bad form | half reps, sagging hips, piked hips, knees on the floor | `half` / `sag` / `pike` / `knees` |
| Conditions | hoodie / loose clothes, dim lamp, cluttered room, rear camera | `loose-clothing` / `dim-light` / `rear-camera` |
| Cheats (expect 0) | head bobbing only, arm waving lying down, sitting and bending elbows, wall push-ups, worm/hip-only, phone shaken over a still person, push-up video on a monitor, two people in frame | `cheat` + the closest other tag (`two-people`, `screen-replay`, …) |

Tips: one set per recording; start recording already in frame or walk in — both are useful; keep sets under 5 minutes
(the recorder stops storing frames after 5 min).
