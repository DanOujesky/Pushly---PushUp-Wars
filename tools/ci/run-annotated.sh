#!/usr/bin/env bash
# Run a command in CI; on failure, publish the important lines of its output as one GitHub error annotation,
# so failures are readable from the Checks API (annotations) without downloading raw logs.
# Usage: tools/ci/run-annotated.sh "<title>" <command> [args...]
set -uo pipefail
title="$1"; shift
log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  {
    echo "--- error lines ---"
    grep -E '^e: |error:|error -|What went wrong|FAILED|Failed test|not ok|Assertion|expected|Expectation failed|Unresolved|Could not|✖|❌' "$log" \
      | grep -vE '^\s+at ' | head -n 70
    echo "--- last lines ---"
    grep -vE '^\s+at ' "$log" | tail -n 25
  } > "$log.summary"
  body="$(sed -e 's/%/%25/g' -e 's/\r//g' "$log.summary" | awk '{printf "%s%%0A", $0}')"
  echo "::error title=${title}::${body}"
fi
exit "$status"
