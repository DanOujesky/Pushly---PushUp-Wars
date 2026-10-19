#!/usr/bin/env bash
# Commit (if message given), push, wait for the given workflows on HEAD, print failures.
# Usage: tools/ci/push-and-wait.sh "<commit message>|" workflow.yml [workflow.yml...]
set -uo pipefail
REPO=DanOujesky/Pushly---PushUp-Wars
msg="$1"; shift
if [ -n "$msg" ]; then
  git add -A && git commit -qm "$msg

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XAQX6LXKkJTWmLCb8DQazL"
fi
git push -q origin main 2>&1 | grep -vE "moved|new location|PushUp-Wars.git"
SHA=$(git rev-parse HEAD)
sleep 25
for wf in "$@"; do
  for i in $(seq 1 90); do
    s=$(gh run list -R $REPO -L 5 --commit "$SHA" -w "$wf" --json status,conclusion -q '.[0] | "\(.status) \(.conclusion)"' 2>/dev/null)
    case "$s" in "completed "*) break;; esac
    sleep 15
  done
  echo "== $wf: $s"
  case "$s" in *failure*) tools/ci/annotations.sh "$wf" "$SHA" | sed -n '/--- error lines ---/,/--- last lines ---/p' | head -60;; esac
done
