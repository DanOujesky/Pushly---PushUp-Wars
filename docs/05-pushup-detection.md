# 05 — Push-up detection (Camera → Pose → RepEngine)

Goal: count **only real, full-range push-ups**, in real time, on device, with the **same results on iOS and Android**.
Targets: ≥ 98 % agreement with human count on the evaluation set; **0 counted reps** on the cheat vectors; ≤ 150 ms from bottom→top lockout to the counter incrementing.

## 1. Pipeline

```
CameraSource ──frames──► PoseEngine (MediaPipe Pose Landmarker, LIVE_STREAM)
                              │  PoseFrame (33 landmarks + world landmarks + visibility)
                              ▼
                         Smoother (One-Euro filter per landmark)
                              ▼
                         FeatureExtractor  ──► per-frame features (angles, depth, line, visibility)
                              ▼
                         PlacementDetector (SIDE / FRONT / UNKNOWN)
                              ▼
                         RepStateMachine ──► RepEvent(counted | rejected(reason)) + live hints
                              ▼
                         RepSessionRecorder ──► compact feature log for the signed rep log (doc 06)
```

Everything from `Smoother` down is the **`RepEngine` module — pure code, identical spec on both platforms**, constants in `shared/rep-engine-spec/pushup-v1.yaml` (code-generated into Swift/Kotlin constants). Never hard-code a threshold in platform code.

## 2. Camera (`CameraSource`)
- Default: **front camera**, 1280×720 @ 30 fps (fallback 640×480 on low-end). Back camera optional (setting "Use rear camera").
- Analysis receives the **latest frame only** (drop frames while busy — `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true`; CameraX `STRATEGY_KEEP_ONLY_LATEST`).
- Orientation: support portrait and landscape; landmarks are normalised to the **upright image** before entering `RepEngine`.
- Exposure: enable low-light boost where available; `FrameQuality` computes mean luma — if too dark for 2 s, hint "Turn on a light".
- Front camera preview is mirrored for the user, but landmarks are **not** mirrored for the engine (document the convention: engine always gets un-mirrored coordinates, left = subject's left).
- iOS: `AVCaptureSession` preset `.hd1280x720`, pixel format `kCVPixelFormatType_32BGRA` for MediaPipe. Android: CameraX `ImageAnalysis` RGBA_8888.

## 3. PoseEngine (MediaPipe Pose Landmarker)
- iOS: `MediaPipeTasksVision` via **Swift Package Manager**. Android: `com.google.mediapipe:tasks-vision`.
- Model: `pose_landmarker_full.task` by default; `pose_landmarker_lite.task` automatically if measured analysis rate < 15 fps for 3 s (device tier cached). `heavy` is not shipped (size/perf).
- Options: running mode `LIVE_STREAM`, `numPoses = 1` (training/wake) — battles also 1 — `minPoseDetectionConfidence 0.5`, `minPosePresenceConfidence 0.5`, `minTrackingConfidence 0.5`, `outputSegmentationMasks = false`.
- Note: on iOS MediaPipe Tasks runs on **CPU only**. Measure on iPhone 12 / 13 / 15 / 17 class devices in the Phase 3 spike; target ≥ 20 fps analysis on iPhone 12+. Android: try GPU delegate, fall back to CPU.
- Output → `PoseFrame`:
```
PoseFrame {
  tMs: Int64                 // monotonic timestamp of the camera frame
  landmarks: [33] {x, y, z, visibility, presence}   // normalised image coords
  world: [33] {x, y, z}      // metres, hip-centred (used for angles)
  imageW, imageH, cameraFacing, rotation
}
```
- Landmark indices (MediaPipe BlazePose 33): nose 0, shoulders 11/12, elbows 13/14, wrists 15/16, hips 23/24, knees 25/26, ankles 27/28, heels 29/30, foot index 31/32.

## 4. Features (per frame)
Computed from normalised image landmarks (in pixels). **Spec v2 (D-062):** the elbow angle uses the **image plane**
(world landmarks squash a straight arm to 120–150° side-on); body line and knee angle still use world landmarks.
FRONT placement is a separate mode (legs hidden) — see §6.

| Feature | Definition |
|---|---|
| `elbowAngle[side]` | angle shoulder–elbow–wrist (degrees) |
| `bodyLine[side]` | angle shoulder–hip–ankle (180° = straight); falls back to shoulder–hip–knee if ankles not visible (then `KNEE_FALLBACK` flag) |
| `kneeAngle[side]` | hip–knee–ankle (detects knee push-ups) |
| `depth` | vertical drop of shoulder midpoint relative to the rep's top position, divided by user upper-arm length (shoulder–elbow, median over calibration) |
| `torsoTilt` | angle between shoulder→ankle line and the image horizontal (plank ≈ 0–35°) |
| `handsUnderShoulders` | horizontal distance wrist–shoulder / shoulder width |
| `visibilityScore[side]` | min visibility over required landmarks of that side |
| `bboxHeight` | body bounding box height / image height (framing: too close / too far) |

**Side selection:** use the side with the higher `visibilityScore` (hysteresis: switch only if the other side is better by > 0.15 for ≥ 10 frames). In FRONT placement use the mean of both sides for elbow angle and the min for visibility.

## 5. Rep state machine

States: `NOT_READY` → `TOP` → `DESCENDING` → `BOTTOM` → `ASCENDING` → (`TOP`, rep evaluated).

Entry conditions (all constants from the YAML; values below are v1 defaults):

| Transition | Condition (must hold for ≥ `stableFrames` = 2 consecutive frames) |
|---|---|
| `NOT_READY → TOP` | plank detected: `torsoTilt ≤ 35°`, `bodyLine ≥ 150°`, `elbowAngle ≥ 155°`, required landmarks visible (`visibility ≥ 0.6`), `0.25 ≤ bboxHeight ≤ 0.95` (side) |
| `TOP → DESCENDING` | `elbowAngle < topElbowMin − hysteresis` (155 − 5 = 150°) |
| `DESCENDING → BOTTOM` | `elbowAngle ≤ bottomElbowMax` (**100°**) **and** `depth ≥ minDepthRatio` (**0.40**) |
| `BOTTOM → ASCENDING` | `elbowAngle > bottomElbowMax + hysteresis` (105°) |
| `ASCENDING → TOP` | `elbowAngle ≥ topElbowMin` (**155°**), or (v2) `elbowAngle ≥ lockoutMinDeg` (**120°**) with the shoulder within **0.45** upper arms of the last full-lockout height → **evaluate rep** |
| any → `NOT_READY` | tracking lost (`visibility < 0.4`) for ≥ 500 ms, or plank lost (standing up, sitting) |
| `DESCENDING → TOP` (no bottom) | elbow returns ≥ 155° without reaching bottom → **reject `NOT_DEEP_ENOUGH`** |

### Rep evaluation (at the end of `ASCENDING → TOP`)
A rep is **counted** only if all hold over the frames of that rep:
1. Reached `BOTTOM` (depth + elbow) — else `NOT_DEEP_ENOUGH`.
2. Reached lockout `elbowAngle ≥ 155°` — else `NO_LOCKOUT` (rep continues waiting up to 3 s, then rejected).
3. `bodyLine ≥ 150°` on ≥ 80 % of rep frames — else `HIPS_SAGGING` (hip below the line) or `HIPS_PIKED` (hip above), decided by the sign of hip deviation from the shoulder–ankle line.
4. `kneeAngle ≥ 150°` on ≥ 80 % of frames — else `KNEES_DOWN` (knee push-ups don't count in v1).
5. Required landmarks visible (`≥ 0.6`) on ≥ 90 % of frames — else `BODY_NOT_VISIBLE`.
6. Duration `minRepMs = 450 ms ≤ duration ≤ maxRepMs = 8000 ms` — else `TOO_FAST` / `TOO_SLOW`.
7. Motion consistency: elbow-angle trajectory is unimodal (one down, one up; ≤ 1 direction reversal tolerated within 8°) — else `IRREGULAR_MOTION`.
8. Anti-cheat hooks pass (doc 06 §2: liveness, frame continuity, single person) — else `INTEGRITY` (not shown as a form hint; shows "Tracking issue").

**Exact v1 order and definitions (D-040):** checks run in the order BODY_NOT_VISIBLE → KNEES_DOWN → HIPS_SAGGING /
HIPS_PIKED → TOO_FAST → TOO_SLOW → IRREGULAR_MOTION → INTEGRITY and the first failure is the reason. `depth` = (shoulder
y − shoulder y at the last TOP) ÷ median upper-arm length (last 30 TOP frames), in image pixels. INTEGRITY v1 = device
motion RMS > `integrity.deviceMotionMaxRms` (0.15 g) on more than 20 % of the rep's frames (phone moved / shaken).
The executable definition is `tools/reference/pushly_ref/rep_engine.py`.

Each counted rep emits `RepEvent.counted(index, tStart, tBottom, tEnd, quality)` where `quality` (0–100) = weighted: depth 35 %, lockout 15 %, body line 30 %, tempo control 20 %. Rejected reps emit `RepEvent.rejected(reason)` and trigger a hint (max one hint per 2 s; same hint max 3× in a row, then show a short illustrated tip).

### Live hints (copy)
| Reason | Hint |
|---|---|
| `NOT_DEEP_ENOUGH` | "Go lower — chest close to the floor" |
| `NO_LOCKOUT` | "Push all the way up" |
| `HIPS_SAGGING` | "Tighten your core — hips up" |
| `HIPS_PIKED` | "Lower your hips — straight line" |
| `KNEES_DOWN` | "Knees off the floor" |
| `BODY_NOT_VISIBLE` | "Move back — I need to see your whole body" |
| `TOO_FAST` | "Control it — full reps only" |

## 6. Placement & calibration
- **Recommended placement: SIDE** — phone on the floor or leaned against a wall/shoe, landscape or portrait, 1.5–2.5 m to the side, lens at floor level. **FRONT** placement (phone on the floor in front of the head, ~1 m) is supported but less precise; in FRONT, depth uses shoulder-to-wrist vertical image distance + face size change, and the bottom threshold is stricter (`frontBottomElbowMax = 95°`).
- **FRONT mode (spec v2, D-062):** locked at plank entry. Visibility = min over both arms; plank = arms straight
  (≥ 155°) and wrists ≥ 1 upper arm below the shoulders; plank lost when the wrists are no longer below the shoulders
  for 500 ms; elbow = mean of both arms; depth from the shoulder midpoint; no body-line / knee checks (not visible).
- `PlacementDetector`: SIDE if shoulder width (image) / torso length (image) < 0.5, FRONT if > 0.9, else UNKNOWN (hint "Turn the phone to face your side").
- **Placement guide screen** before each session (skippable after 5 sessions): live preview with a silhouette overlay; turns green when the full body fits.
- **Calibration** (onboarding + whenever the user asks): 3 reps → store `upperArmLength`, `topElbowTypical`, `bottomElbowTypical`, `placement`. Per-user adaptation is allowed **only within bounds**: `bottomElbowMax` ∈ [90°, 105°], `minDepthRatio` ∈ [0.35, 0.50]. Ranked battles and leaderboards always use bounds ≥ the defaults (personal adaptation may only make it *stricter* for competitive sessions).

## 7. Performance budget
| Item | Budget |
|---|---|
| Camera open → first analysed frame | ≤ 1.0 s (warm), ≤ 2.0 s (cold) |
| Pose inference | ≤ 50 ms per frame on target devices |
| RepEngine per frame | ≤ 1 ms |
| Counter update after lockout | ≤ 150 ms |
| Battery | ≤ 8 % per 10 min session on iPhone 13 / Pixel 7 |
- Pre-warm the landmarker when the ring screen appears (before the user taps Start).
- Handle thermal state: at `serious` thermal state switch to lite model and 15 fps.

## 8. Test vectors (shared/test-vectors/pushup)
- Format: see `shared/test-vectors/README.md`. Each vector = recorded `PoseFrame` sequence + human-labelled expected result.
- Both `RepEngine` implementations run **all** vectors in unit tests (CI fails on any mismatch with the expected count or with the other platform's output).
- Required coverage before Phase 3 is done (≥ 200 vectors, ≥ 30 different people):
  - body types, sexes, heights; clothing (tight, loose, dark, hoodie); lighting (daylight, lamp, dim); backgrounds (cluttered, mirror); placements (side L/R, front, rear camera); speeds (slow, normal, fast); fatigue (last reps of a max set).
  - **Negative/cheat vectors (expect 0 reps):** half reps, head bobbing only, arm waving while lying, knee push-ups, sitting and bending elbows, standing wall push-ups, hip-only "worm" motion, phone shaken over a still person, video of push-ups played on another screen/monitor, printed photo moved, two people in frame, a doll/mannequin.
- Tool: debug-only **Pose recorder** screen (Wake tab, debug builds) records PoseFrames; the set is labelled on the phone (human count, placement, tags) and shared as JSON; `tools/pose-recorder/import.py` adds it to the vectors. No video is recorded (D-041). How-to: `docs/qa/pose-recording.md`.
- Until real recordings exist, 25 synthetic vectors (`synthetic-*`, generated by `tools/reference/pushly_ref/pushup_scenarios.py` from a kinematic body model) cover good reps, every form error and every cheat type that can be simulated.

## 9. Future (not v1)
- **Learned validator:** small temporal model (1D-CNN or GRU on feature sequences) trained on the labelled vectors, run as a **second opinion** after the heuristic engine (Core ML / LiteRT). Used first only for anti-cheat scoring, never as the sole counter.
- Other exercises (`exercise_type`: squat, sit-up) reuse the same pipeline with different specs.
