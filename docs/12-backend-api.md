# 12 — Backend API (Edge Functions, RPCs, Realtime, cron)

All request/response bodies are defined as JSON Schemas in `shared/contracts/` and code-generated into Swift (`Codable`) and Kotlin (`kotlinx.serialization`) models. Edge Functions validate input against the same schemas (Zod generated from JSON Schema or `ajv`).

Error format (all functions):
```json
{ "error": { "code": "VALIDATION_FAILED", "message": "human readable", "retryable": false, "details": {} } }
```
Codes: `UNAUTHENTICATED`, `FORBIDDEN`, `VALIDATION_FAILED`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`, `INTEGRITY_FAILED`, `UPGRADE_REQUIRED`, `INTERNAL`. Clients retry only when `retryable = true` (outbox, doc 03 §5).

## 1. Edge Functions (Deno/TypeScript, `supabase/functions/<name>`)
| Function | Auth | Purpose |
|---|---|---|
| `register-device` | user | Register device + App Attest attestation / Play Integrity verdict + public key. Returns `deviceId`. |
| `submit-rep-session` | user + device assertion | Validate signed rep log (doc 06 §4); write `rep_sessions`, logs, stats, wake attempt, streak, clan war tally, PRs, achievements — **one transaction** via SQL function `app.apply_validated_session(...)`. Returns authoritative result (wake status, points, streak, totals, new achievements). Idempotent by `sessionId`. |
| ~~`sync-alarms`~~ | user | Implemented as the Postgres RPC `sync_alarms(changes jsonb)` (D-036, see §2). |
| `wake-schedule-ack` | user | Device reports its scheduling window state (for the "alarms run out" safety push, doc 04 §5.3). |
| `matchmaking-join` / `matchmaking-leave` | user | Queue management (doc 07 §3). |
| `battle-create-invite` / `battle-respond-invite` | user | Friend battles + share codes. |
| `battle-token` | participant | Mint LiveKit access token for room `battle-{id}` (identity = user id, grants publish/subscribe, TTL 15 min). |
| `battle-clock` | user | Returns `{ serverMs }` for clock sync (fast path, no DB). |
| `battle-ready` | participant | Mark ready; when both ready → status `countdown`, broadcast `start`. |
| `settle-battle` | internal (called by `submit-rep-session` or cron timeout) | Doc 07 §4.7, trophies + MMR + ledger. |
| `clan-*` | user | `create`, `update`, `join`, `leave`, `request`, `respond-request`, `invite`, `kick`, `promote`, `demote`, `transfer`, `disband` — or implement as Postgres RPCs (preferred when pure DB logic). |
| `revenuecat-webhook` | RevenueCat shared secret | Update `entitlements`, `profiles.is_pro`. |
| `push-send` | internal | Send APNs (token-based auth, `.p8`) / FCM v1 messages from `push_outbox`. |
| `account-delete` | user (recent re-auth) | Schedule deletion, revoke sessions. |
| `data-export` | user | GDPR export (JSON zip to a signed URL valid 24 h). |
| `admin-*` | moderator role | Moderation actions (doc 06 §6). |

## 2. Postgres RPCs (`supabase.rpc(...)`, `SECURITY DEFINER`, `set search_path = public, app`)
| RPC | Notes |
|---|---|
| `sync_alarms(changes jsonb)` | Upserts/soft-deletes the caller's alarms from the device outbox (optimistic concurrency on `version`; same/older version → newer `updatedAt` wins, else conflict + server copy). Validates with the shared rules, writes `alarm_schedule_versions`, returns per-change results + all alarms (restore). |
| `update_profile(patch jsonb)` | whitelisted columns only; username change max 1 / 30 days |
| `search_users(q text)` | username prefix search, respects visibility & blocks, limit 20 |
| `send_friend_request(to uuid)`, `respond_friend_request(from uuid, accept bool)`, `remove_friend(u uuid)`, `block_user(u uuid)` | max 500 friends |
| `get_leaderboard(board, scope, scope_key, period_key, offset, limit)` | from snapshots or live for friends/clan |
| `my_rank(board, scope, scope_key, period_key)` | doc 08 §4.1 |
| `get_stats(period text)` | personal dashboard payload |
| `battle_push_rep(battle_id, round, rep_index, t_end_server_ms, quality)` | participant & live check; idempotent by unique key |
| `send_clan_message(body text)`, `react_clan_message(id, emoji)`, `delete_clan_message(id)` | rate limits (doc 09 §5) |
| `equip_item(item_id)` | cosmetics |
| `report(target jsonb, reason text, details text)` | |

## 3. Realtime channels
| Channel | Type | Payloads |
|---|---|---|
| `user:{uid}` (private) | broadcast | `match_found`, `battle_invite`, `friend_request`, `achievement_unlocked`, `session_validated` |
| `battle:{id}` (private, participants) | broadcast + presence | `start {startAtServerMs}`, `score {a,b,round}`, `round_end`, `settled {winner, deltas}`; presence = connection state |
| `clan:{id}` (private, members) | postgres_changes on `clan_messages` + broadcast | chat, system events |
| `clan_war:{warId}` (members of both clans) | broadcast | `score {a, b}` throttled 5 s |

Use Supabase Realtime **private channels with authorization policies** (RLS on `realtime.messages`) so only allowed users can join.

## 4. Scheduled jobs (`pg_cron`, all UTC)
| Job | Schedule | Action |
|---|---|---|
| `matchmake` | every 2 s (pg_cron sub-minute seconds syntax) or trigger | pair queue (doc 07 §3) |
| `matchmaking_purge` | every 1 min | drop stale queue rows |
| `battle_timeouts` | every 10 s | settle/void stuck battles |
| `leaderboard_refresh` | every 1 min | refresh `leaderboard_snapshots` |
| `wake_decide_missed` | every 5 min | mark attempts `missed` after deadline + 48 h upload grace for final decision (provisional `missed` shown earlier) |
| `daily_alarm_refresh_push` | hourly | silent push to users whose local time is 03:00 (doc 04 §5.3) |
| `alarm_window_warning` | hourly | visible push if a device hasn't acked its window for 5 days |
| `clan_war_lock_rosters` | Sun 23:00 | snapshot participating clans & rosters |
| `clan_war_finalize_and_match` | Mon 00:00 | finalize last week, then `clan_war_matchmake()` |
| `season_rollover` | 1st of month 00:05 | season rewards, soft reset (doc 08 §2.5) |
| `retention_purge` | daily 02:00 | doc 11 §11 |
| `trust_recovery` | weekly | +1 trust for clean users (doc 06 §1) |

## 5. Push notifications (via `push_outbox` → `push-send`)
Types & default on/off — see doc 15. Every push carries a deep link (`pushly://...`) and a `collapse_id` / `tag`.

## 6. Rate limits
Implemented in a shared SQL helper `app.check_rate(user, key, limit, window)` backed by the `rate_limits` table (doc 11 §8):
- `submit-rep-session` 120/h, `matchmaking-join` 60/h, friend requests 50/day, clan messages per doc 09, username searches 60/min.

## 7. Security checklist for every function
- Verify JWT (`supabase.auth.getUser()`), never trust `userId` from the body.
- Validate payload with the generated schema; reject unknown fields.
- Use the service-role client **only** inside functions; never ship it to clients.
- All money/entitlement logic only from RevenueCat webhook (signature/secret verified).
- Log decisions affecting competition to `audit_log`.
