#!/usr/bin/env bash
# Print the success summaries (notice annotations) of the latest run of a workflow: tools/ci/notices.sh <workflow.yml> [sha]
set -euo pipefail
REPO=DanOujesky/Pushly---PushUp-Wars
SHA=${2:-$(git rev-parse HEAD)}
R=$(gh run list -R $REPO -L 20 --commit "$SHA" -w "$1" --json databaseId -q '.[0].databaseId')
for J in $(gh api repos/$REPO/actions/runs/$R/jobs -q '.jobs[].id'); do
  gh api repos/$REPO/check-runs/$J/annotations -q '.[] | select(.annotation_level=="notice") | .title + "\n" + .message'
done
