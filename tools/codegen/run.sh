#!/usr/bin/env bash
# Regenerate all platform code from shared/ (CLAUDE.md §9). Pass --check in CI.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 tools/codegen/check_contrast.py
python3 tools/codegen/generate.py "$@"
