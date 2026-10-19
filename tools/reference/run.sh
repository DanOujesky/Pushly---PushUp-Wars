#!/usr/bin/env bash
# Test the reference implementations and verify the generated test vectors are current. Pass nothing to check,
# or --write to regenerate the vectors.
set -euo pipefail
cd "$(dirname "$0")"
python3 -m unittest discover -s . -p 'test_*.py'
if [ "${1:-}" = "--write" ]; then python3 build_vectors.py; else python3 build_vectors.py --check; fi
