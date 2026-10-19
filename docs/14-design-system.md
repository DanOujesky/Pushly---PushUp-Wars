# 14 — Design system

Brand feel: **arena energy** — bold, fast, competitive, but clean. Dark mode is the hero (mornings, gym vibe); light mode fully supported.
All values live in `shared/design-tokens/tokens.json` and are generated into `DesignSystem` (Swift) and `:core:designsystem` (Kotlin). No raw values in feature code.

## 1. Color tokens
| Token | Dark | Light | Use |
|---|---|---|---|
| `bg.base` | #0B0B12 | #F6F6FA | app background |
| `bg.surface` | #151522 | #FFFFFF | cards |
| `bg.elevated` | #1F1F31 | #FFFFFF (+shadow) | sheets, popovers |
| `stroke.subtle` | #2A2A40 | #E4E4EE | dividers, card borders |
| `text.primary` | #F5F5FA | #12121C | |
| `text.secondary` | #A3A3B8 | #5B5B70 | |
| `text.tertiary` | #6E6E85 | #8C8CA0 | |
| `brand.flame` | #FF5A1F | #F04E12 | primary actions, wake |
| `brand.volt` | #7B5CFF | #6A4BF0 | battles |
| `brand.lime` | #C6FF3D | #6FA800 | highlights, PRs, success accents |
| `brand.cyan` | #22D3EE | #0891B2 | training, info |
| `state.success` | #22C55E | #16A34A | |
| `state.warning` | #F59E0B | #D97706 | |
| `state.danger` | #EF4444 | #DC2626 | |
| `league.bronze/silver/gold/platinum/diamond/champion/legend` | #C77B4A / #C0C7D6 / #F5C542 / #4FD1C5 / #6EA8FF / #FF6B9A / gradient flame→volt | same | league badges |

Gradients: `gradient.hero` flame→volt (135°), `gradient.success` lime→cyan, `gradient.chartFill` series color 40 % → 0 % opacity (top→bottom).

Contrast: all text ≥ 4.5:1 on its background (verify in CI with a token contrast script); chart colors ≥ 3:1 against the surface.

### Chart palette (doc 10)
- Categorical (contexts): wake = `brand.flame`, battle = `brand.volt`, training = `brand.cyan`; 4th/5th series: `brand.lime`, #F472B6.
- Sequential (heatmap, 5 steps): from `bg.surface` mixed 15 % lime → 100 % lime (dark), equivalent in light.
- Never encode meaning by color alone: use labels, legends, patterns for success/fail (filled vs. hollow dots).

## 2. Typography
- Text: system fonts (**SF Pro** on iOS, **Roboto Flex** / system on Android) for full Dynamic Type / font-scale support.
- Numbers & display: **Barlow Condensed** (SIL OFL) — Bold/ExtraBold, tabular figures for counters.

| Token | Size / line | Weight | Font |
|---|---|---|---|
| `display.counter` | 120 / 120 (scales with screen, min 88) | ExtraBold | Barlow Condensed |
| `display.xl` | 48 / 52 | Bold | Barlow Condensed |
| `display.l` | 34 / 40 | Bold | Barlow Condensed |
| `title.l` | 28 / 34 | Bold | System |
| `title.m` | 22 / 28 | Semibold | System |
| `title.s` | 17 / 22 | Semibold | System |
| `body` | 17 / 22 | Regular | System |
| `body.s` | 15 / 20 | Regular | System |
| `caption` | 12 / 16 | Medium | System |
| `overline` | 11 / 14, +8 % tracking, uppercase | Bold | System |

## 3. Spacing, radii, elevation
- Spacing scale (pt/dp): 2, 4, 8, 12, 16, 20, 24, 32, 40, 56. Screen gutter 16; card padding 16; section gap 24.
- Radii: `r.s` 8, `r.m` 14, `r.l` 22, `r.pill` 999. Cards `r.l`.
- Elevation (light mode only shadows; dark mode uses `bg.elevated` + 1 px `stroke.subtle`).

## 4. Components (build in Phase 1, with previews/snapshots)
`PrimaryButton` (gradient.hero, 56 tall, pressed scale 0.97), `SecondaryButton`, `GhostButton`, `IconButton`, `Card`, `StatTile` (value + label + Δ + sparkline), `SegmentedControl`, `Chip`, `Toggle`, `Stepper` (rep target), `TimeWheel` (alarm time), `WeekdayTimeGrid` (per-weekday times), `Avatar` (+ league ring + clan tag), `LeagueBadge`, `TrophyCounter` (animated rolling digits), `RepCounter` (huge, pop animation), `ProgressRing`, `CountdownRing`, `BodyFrameOverlay` (silhouette, red→green), `HintToast`, `HealthBanner`, `EmptyState`, `Skeleton`, `LeaderboardRow` (+ podium variant), `ChatBubble`, `BottomSheet`, `ConfettiView`, `ShareCard` templates, chart wrappers (`BarChartView`, `AreaChartView`, `LineChartView`, `DotTimeChartView`, `HeatmapView`, `DonutView`).

## 5. Motion
| Token | Duration | Curve | Use |
|---|---|---|---|
| `motion.fast` | 120 ms | ease-out | taps, toggles |
| `motion.base` | 240 ms | ease-in-out | transitions |
| `motion.slow` | 600 ms | spring (damping 0.8) | chart entry, results |
| `motion.pop` | 180 ms | spring (stiff) | rep counter pop (scale 1 → 1.18 → 1) |
- Respect Reduce Motion / "Remove animations": replace movement with cross-fades, disable confetti.

## 6. Haptics & sound
| Event | iOS | Android |
|---|---|---|
| Rep counted | `.impact(.light)` | `EFFECT_TICK` |
| Rep rejected | `.notification(.warning)` | `EFFECT_DOUBLE_CLICK` |
| Goal reached / win | `.notification(.success)` | `EFFECT_HEAVY_CLICK` + pattern |
| Countdown 3-2-1 | `.impact(.medium)` each | `EFFECT_CLICK` each |
Sounds (bundled, ≤ 1 s, normalised −16 LUFS): rep tick, rejected blip, goal jingle, battle start horn, win/lose stingers. Alarm sounds: ≥ 12 bundled (energetic, gentle, classic bell, drill sergeant voice "Get down and give me twenty!", etc.) — must be original or properly licensed (decisions log).

## 7. Iconography & illustration
- SF Symbols on iOS, Material Symbols Rounded on Android, mapped by a shared icon-name table; custom icons (push-up pose, trophy, clan shield) as vector assets in both.
- Mode illustrations: simple bold line illustrations, one per wake mode and battle mode.
- App icon: stylised push-up silhouette forming an upward arrow / "P", flame→volt gradient background.

## 8. Key screen layouts (wireframe notes)
- **Wake camera:** full-bleed camera preview; top: mode + timer pill; center-top: `RepCounter` with "/ 20"; bottom: hint toast area + `BodyFrameOverlay`; give-up link small in a corner. Everything readable from 2 m (counter ≥ 88 pt).
- **Ring screen (Android):** time huge, label, mode card, giant "Start push-ups" button occupying the bottom third.
- **Battle:** split screen per doc 07 §6.
- **Alarm editor:** list of sections: Schedule (weekday grid with per-day time), Overrides (mini calendar), Challenge mode (cards with illustrations), Target, Sound, Advanced.
