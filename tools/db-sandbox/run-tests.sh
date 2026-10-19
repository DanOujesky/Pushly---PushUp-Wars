#!/usr/bin/env bash
# Run Supabase migrations + database tests against a plain Postgres (no Supabase CLI / Docker needed).
# Preferred in normal development: `supabase db reset && supabase test db`.
# This script is the fallback used in CI job `supabase.yml` (sandbox step) and in environments without Docker.
#
# Usage: PGHOST=localhost PGUSER=postgres tools/db-sandbox/run-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${PUSHLY_TEST_DB:-pushly_test}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

dropdb --if-exists "$DB" >/dev/null
createdb "$DB"

"${PSQL[@]}" -d "$DB" -f "$ROOT/tools/db-sandbox/supabase_stub.sql" >/dev/null

if "${PSQL[@]}" -d "$DB" -tAc "select 1 from pg_available_extensions where name = 'pgtap'" | grep -q 1; then
  "${PSQL[@]}" -d "$DB" -c "create extension pgtap" >/dev/null
else
  "${PSQL[@]}" -d "$DB" -f "$ROOT/tools/db-sandbox/pgtap_shim.sql" >/dev/null
fi

for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "migrate  $(basename "$f")"
  "${PSQL[@]}" -d "$DB" -f "$f" >/dev/null
done

if [ -f "$ROOT/supabase/seed.sql" ]; then
  "${PSQL[@]}" -d "$DB" -f "$ROOT/supabase/seed.sql" >/dev/null
fi

failed=0
cd "$ROOT/supabase/tests"
for t in [0-9]*.sql; do
  out="$("${PSQL[@]}" -tA -d "$DB" -f "$t" 2>&1)" || { echo "ERROR    $t"; echo "$out"; failed=1; continue; }
  if echo "$out" | grep -Eq '^not ok|^# Looks like'; then
    echo "FAIL     $t"; echo "$out" | grep -E '^not ok|^# ' ; failed=1
  else
    echo "pass     $t ($(echo "$out" | grep -c '^ok') assertions)"
  fi
done

exit $failed
