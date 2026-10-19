#!/usr/bin/env bash
# Print failure annotations for the latest run of a workflow on a commit: tools/ci/annotations.sh <workflow.yml> [sha]
set -euo pipefail
REPO=DanOujesky/Pushly---PushUp-Wars
SHA=${2:-$(git rev-parse HEAD)}
R=$(gh run list -R $REPO -L 20 --commit "$SHA" -w "$1" --json databaseId -q '.[0].databaseId')
for J in $(gh api repos/$REPO/actions/runs/$R/jobs -q '.jobs[] | select(.conclusion=="failure") | .id'); do
  gh api repos/$REPO/check-runs/$J/annotations -q '.[] | select(.annotation_level=="failure") | .title + "\n" + .message'
done
