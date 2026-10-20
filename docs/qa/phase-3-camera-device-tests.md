# Phase 3 — camera & rep counting: device tests

What CI already proves: the rep engine (Swift + Kotlin) reproduces the reference engine on all vectors, counts
good reps, rejects every simulated form error and cheat, and the session model finishes a wake challenge at its
target. What only a real phone can prove is below. Android: install `pushly-debug-apk` from the latest `android` run.

## Free training (Wake tab → Free training)
| # | Test | Expected |
|---|---|---|
| CAM-01 | First open | Camera explainer screen first; system permission only after "Allow camera". Deny → explainer with "Open settings". |
| CAM-02 | Phone on the floor, side view, 10 good push-ups | Counter 10 (±0), "+1" haptic each rep, skeleton overlay follows the body. |
| CAM-03 | 5 half reps | 0 counted, hint "Go lower — chest close to the floor". |
| CAM-04 | Knee push-ups | 0 counted, hint "Knees off the floor". |
| CAM-05 | Sagging hips / piked hips | hint "Tighten your core — hips up" / "Lower your hips — straight line". |
| CAM-06 | Walk out of frame | Guidance "Step into the frame"; counting resumes when back in plank. |
| CAM-07 | Dark room | "Turn on a light" guidance. |
| CAM-08 | Front view (phone in front of the head) | Counts (less precise); guidance mentions side view if placement is unclear. |
| CAM-09 | Voice counting on | Counts are spoken. |
| CAM-10 | End → summary | Reps, average form %, duration, most common rejection. |
| CAM-11 | Rotate the phone during the session | Overlay stays aligned; counting not broken. |
| CAM-12 | 10-minute session | No stutter; note the phone's temperature and battery drop (budget ≤ 8 %). |

## Wake challenge
| # | Test | Expected |
|---|---|---|
| CAM-20 | Alarm rings → Start push-ups | Camera session with the target; counter shows "x / target". |
| CAM-21 | Reach the target | Challenge completes, alarm stops, success screen. |
| CAM-22 | Cheat (arm waving lying in bed) | Never completes; alarm escalation continues ("Back to alarm" returns to ringing). |
| CAM-23 | Shake the phone while doing reps | Reps rejected as "Tracking issue" (INTEGRITY). |

## Performance spike (P3-01) — please note per phone
Phone model, average fps shown in the debug overlay if visible, time from opening to the first skeleton, whether the
lite model kicked in (phone got hot). Send the notes to Claude; they become the P3-01 report.

## Recording vectors
See `docs/qa/pose-recording.md`.
