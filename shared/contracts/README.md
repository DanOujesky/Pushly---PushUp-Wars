# Contracts

JSON Schema (draft 2020-12) for every payload crossing a boundary. Generated into Swift/Kotlin models and used for server-side validation (doc 12). Create these in Phase 0/when first needed:

| File | Used by |
|---|---|
| `alarm-schedule.schema.json` | `sync-alarms`, local persistence (doc 04 §2) |
| `rep-log.schema.json` | `submit-rep-session` (doc 06 §3) |
| `submit-rep-session.response.schema.json` | wake result, points, streak, achievements |
| `battle-events.schema.json` | LiveKit data-channel + Realtime payloads (doc 07 §4) |
| `realtime-events.schema.json` | `user:{uid}`, `battle:{id}`, `clan:{id}`, `clan_war:{id}` payloads (doc 12 §3) |
| `leaderboard.schema.json` | `get_leaderboard`, `my_rank` |
| `stats.schema.json` | `get_stats` |
| `error.schema.json` | all functions (doc 12) |
| `analytics-events.md` | event names & properties (doc 03 §8) |

Rules: additive changes only within a major version; breaking changes require a new schema version + min-app-version bump in `app_config`.

## Fixtures
`fixtures/*.json` are example payloads exactly as the backend returns them (PostgREST rows). Both apps decode them in
unit tests, so a model that drifts from the database fails on both platforms. Update a fixture together with the migration
that changes the shape.
