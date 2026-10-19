#!/usr/bin/env bash
# Run a command in CI; on failure, publish the last 80 lines of its output as one GitHub error annotation,
# so failures are readable from the Checks API (annotations) without downloading raw logs.
# Usage: tools/ci/run-annotated.sh "<title>" <command> [args...]
set -uo pipefail
title="$1"; shift
log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  body="$(tail -n 80 "$log" | sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}')"
  echo "::error title=${title}::${body}"
fi
exit "$status"
