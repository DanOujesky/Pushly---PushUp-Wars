# 14 — Design system

Brand feel: **arena energy** — bold, fast, competitive, but clean. Approved concept: Design canvas "Pushly — app design concept" (Launch, Welcome, Sign in, Profile setup, Wake tab, Update required).
**The app is dark-only for now (D-033)**: both apps force the dark appearance. Light token values are kept valid (contrast-checked) for a possible future theme setting.
All values live in `shared/design-tokens/tokens.json` and are generated into `DesignSystem` (Swift) and `:core:designsystem` (Kotlin) by `tools/codegen/run.sh`. No raw values in feature code.

## 1. Color tokens
| Token | Dark | Light | Use |
|---|---|---|---|
| `bg.base` | #0A0A10 | #F6F6FA | app background |
| `bg.surface` | #14141E | #FFFFFF | cards, fields, tab bar |
| `bg.elevated` | #1C1C2A | #FFFFFF | sheets, menus, dialogs |
| `stroke.subtle` | #23233A | #E4E4EE | dividers, card & field borders |
| `stroke.strong` | #33334A | #C9C9D6 | inactive page dots, emphasised outlines |
| `text.primary` | #F4F4F8 | #12121C | |
| `text.secondary` | #A8A8BC | #5B5B70 | body copy under titles |
| `text.tertiary` | #8C8CA0 | #6E6E85 | labels, captions (≥ 4.5:1) |
| `text.disabled` | #6E6E85 | #A3A3B8 | placeholders, inactive tabs (not for essential text) |
| `brand.flame` | #FF5A1F | #F04E12 | primary actions, wake, focus ring |
| `brand.flameText` | #FF7A45 | #C2410C | flame-tinted text / selected tab |
| `brand.volt` | #7B5CFF | #6A4BF0 | battles |
| `brand.voltText` | #9B84FF | #5B3FD6 | volt-tinted text |
| `brand.lime` | #C6FF3D | #679C00 | highlights, PRs |
| `brand.cyan` | #22D3EE | #0891B2 | clans, training, info |
| `state.success` / `state.successText` | #22C55E / #4ADE80 | #16A34A / #15803D | valid field border / success text |
| `state.warning` | #F59E0B | #D97706 | |
| `state.danger` | #EF4444 | #DC2626 | |
| `league.bronze/silver/gold/platinum/diamond/champion/legend` | #C77B4A / #C0C7D6 / #F5C542 / #4FD1C5 / #6EA8FF / #FF6B9A / gradient flame→volt | same | league badges |

Gradients: `gradient.hero` flame→volt (135°) — primary buttons, logo mark, progress bars; `gradient.success` lime→cyan; `gradient.chartFill` series color 40 % → 0 % opacity.
Glow: primary buttons and the logo mark cast a flame shadow (30–35 % opacity, ~32 pt blur, 12 pt y-offset). Screens use one soft radial "glow spot" (flame, volt or cyan, 22–32 % opacity) behind hero content — never more than one per screen.

Contrast: all text pairs ≥ 4.5:1, graphics ≥ 3:1, both themes — enforced by `tools/codegen/check_contrast.py` in CI.

### Chart palette (doc 10)
- Categorical (contexts): wake = `brand.flame`, battle = `brand.volt`, training = `brand.cyan`; 4th/5th series: `brand.lime`, #F472B6.
- Sequential (heatmap, 5 steps): from `bg.surface` mixed 15 % lime → 100 % lime.
- Never encode meaning by color alone: use labels, legends, patterns for success/fail (filled vs. hollow dots).

## 2. Typography
Two bundled font families (SIL OFL 1.1, files + licences in `shared/design-tokens/fonts/`, copied into both apps by codegen — D-034):
- **Barlow Condensed** — display: screen titles (ExtraBold, UPPERCASE), big numerals (Black Italic), wordmark, labels.
- **Figtree** — all UI text (Regular / Medium / SemiBold / Bold).
Every token scales with Dynamic Type / font scale (iOS `relativeTo:` text style, Android `sp`). Illustrations (avatar initials, onboarding art) may use fixed sizes.

| Token | Size / line | Weight | Font | Notes |
|---|---|---|---|---|
| `display.counter` | 150 / 128 (min 96) | Black Italic | Barlow Condensed | rep counter |
| `display.time` | 96 / 86 | Black Italic | Barlow Condensed | alarm time |
| `display.logo` | 64 / 58 | Black Italic, uppercase | Barlow Condensed | launch wordmark |
| `display.xl` | 48 / 46 | ExtraBold, uppercase | Barlow Condensed | hero titles |
| `display.l` | 44 / 42 | ExtraBold, uppercase | Barlow Condensed | screen titles |
| `display.m` | 32 / 32 | ExtraBold, uppercase | Barlow Condensed | tab headers |
| `display.wordmark` | 26 / 28 | Black Italic, uppercase | Barlow Condensed | small wordmark |
| `stat` | 44 / 44 | Black Italic | Barlow Condensed | stat tiles |
| `name` | 28 / 30 | ExtraBold | Barlow Condensed | usernames |
| `label.display` / `label.logo` | 22 / 24, 18 / 22, tracked uppercase | SemiBold | Barlow Condensed | "of 20 push-ups", "PushUp Wars" |
| `title.l` / `title.m` / `title.s` | 28 / 22 / 17 | Bold | Figtree | |
| `button` | 17 / 22 | Bold | Figtree | |
| `body` | 17 / 24 | Regular | Figtree | |
| `body.s` | 15 / 20 | Medium | Figtree | |
| `caption` | 13 / 18 | Regular | Figtree | |
| `overline` | 13 / 16, +8 % tracking, uppercase | Bold | Figtree | field & section labels |
| `tab` | 11 / 14 | Bold | Figtree | tab bar |

## 3. Spacing, radii, elevation
- Spacing scale (pt/dp): 2, 4, 8, 12, 16, 20, 24, 32, 40, 56. Screen side padding 24; card padding 16–20; section gap 24.
- Radii: `r.s` 12 (swatches, chips), `r.m` 18 (buttons, fields, banners), `r.l` 24 (cards), `r.xl` 32 (hero panels), `r.pill` 999.
- Elevation: no grey drop shadows; surfaces are `bg.surface` / `bg.elevated` + 1 px `stroke.subtle`. Only gradient elements glow.
- Primary button 58 tall; fields 56 tall with an uppercase `overline` label above and the message below; focus = flame border, valid = success border + check, error = danger border.

### Brand mark
Gradient (`gradient.hero`) rounded square (corner = 28.6 % of size) with the white push-up glyph drawn on a 64-unit grid: body `M14,40 L30,40 L38,28 L50,28`, arrow `M44,20 L52,28 L44,36` (stroke 6, round caps/joins), head circle r 6 at (18,26). Same geometry in `LogoMark` (iOS + Android), the iOS app icon (`AppIcon.png`) and the Android adaptive icon (`ic_launcher_foreground.xml`).

## 4. Components (build in Phase 1, with previews/snapshots)
`PrimaryButton` (gradient.hero + flame glow, 58 tall, pressed scale 0.97), `SecondaryButton`, `GhostButton`, `IconButton`, `SectionLabel`, `ScreenTitle`, `PushlyTextField`, `PickerField`, `Pill`, `InlineBanner`, `GradientProgressBar`, `PageDots`, `GlowSpot` / arena background, `LogoMark`, `Wordmark`, `Card`, `StatTile` (value + label + Δ + sparkline), `SegmentedControl`, `Chip`, `Toggle`, `Stepper` (rep target), `TimeWheel` (alarm time), `WeekdayTimeGrid` (per-weekday times), `Avatar` (+ league ring + clan tag), `LeagueBadge`, `TrophyCounter` (animated rolling digits), `RepCounter` (huge, pop animation), `ProgressRing`, `CountdownRing`, `BodyFrameOverlay` (silhouette, red→green), `HintToast`, `HealthBanner`, `EmptyState`, `Skeleton`, `LeaderboardRow` (+ podium variant), `ChatBubble`, `BottomSheet`, `ConfettiView`, `ShareCard` templates, chart wrappers (`BarChartView`, `AreaChartView`, `LineChartView`, `DotTimeChartView`, `HeatmapView`, `DonutView`).

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
