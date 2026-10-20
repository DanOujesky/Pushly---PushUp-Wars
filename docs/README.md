# Pushly documentation index

| # | Doc | What it answers |
|---|---|---|
| — | [Status](STATUS.md) | What's done, verified, unverified — read first |
| — | [Development setup](DEVELOPMENT.md) | Tools, commands, Windows/Mac/CI |
| — | [Releasing test builds](RELEASING.md) | TestFlight + Google Play from GitHub Actions, secrets setup |
| 01 | [Product vision](01-product-vision.md) | Why Pushly exists, target users, principles, success metrics |
| 02 | [Product spec](02-product-spec.md) | Every screen, flow and rule from the user's point of view |
| 03 | [Architecture](03-architecture.md) | Modules, data flow, client ↔ server responsibilities |
| 04 | [Alarm system](04-alarm-system.md) | Alarm schedule model, challenge modes, iOS AlarmKit + Android implementation |
| 05 | [Push-up detection](05-pushup-detection.md) | Camera → pose → rep engine pipeline, thresholds, calibration |
| 06 | [Anti-cheat](06-anti-cheat.md) | Client + server validation, trust score, review flow |
| 07 | [Battles](07-battles.md) | Battle modes, matchmaking, realtime protocol, split-screen video |
| 08 | [Ranking & leaderboards](08-ranking-leaderboards.md) | Trophies, MMR, leagues, seasons, leaderboard types |
| 09 | [Clans & Clan Wars](09-clans.md) | Clan lifecycle, roles, weekly war matching and scoring |
| 10 | [Stats & progress](10-stats-progress.md) | Metrics, charts, achievements, streaks |
| 11 | [Data model](11-data-model.md) | Full Postgres schema, RLS, indexes |
| 12 | [Backend API](12-backend-api.md) | Edge Functions, RPCs, realtime channels, cron jobs |
| 13 | [Monetization](13-monetization.md) | Ads placement rules, Pushly Pro, RevenueCat |
| 14 | [Design system](14-design-system.md) | Brand, tokens, components, motion, haptics, sound |
| 15 | [Social & notifications](15-social-notifications.md) | Friends, invites, push notifications |
| 16 | [Privacy, security & compliance](16-privacy-security-compliance.md) | GDPR, store review, permissions, data retention |
| 17 | [Roadmap](17-roadmap.md) | Phased task list with acceptance criteria — **build in this order** |
| 18 | [Testing & QA](18-testing-qa.md) | Test strategy, test vectors, device matrix, release checklist |
| 19 | [Decisions log](19-decisions-log.md) | ADRs, dependencies, open questions |

Glossary:

- **Wake Challenge** — the user's enrolment in the morning alarm game. One active challenge per user.
- **Wake mode** — the rule the alarm uses (e.g. *Ring Until Done*, *Beat the Clock*). See doc 04.
- **Rep** — one valid push-up as accepted by the `RepEngine`.
- **Rep session** — one continuous camera session producing reps (a wake attempt, a battle round, a free training).
- **Rep log** — the signed, compact record of a rep session sent to the server for validation.
- **Battle** — a real-time push-up duel between two users.
- **Trophies** — visible competitive points from battles. **MMR** — hidden skill rating for matchmaking.
- **Clan War** — weekly contest between two clans; score = sum of verified reps of members during the week.
- **Pushly Pro** — paid membership (no ads + extras, never competitive advantage).
