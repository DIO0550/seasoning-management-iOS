#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Validate the harness before reading PostToolUse JSON as data in Python.
if ! python3 "$repo_root/harness/check.py"; then
  echo "Harness configuration is inconsistent. Fix the references/settings before continuing." >&2
  exit 2
fi

if ! format_feedback=$(python3 "$repo_root/harness/swift-format.py" lint --post-edit 2>&1); then
  printf '%s\n' "$format_feedback" >&2
  exit 2
fi

printf '%s\n' "$format_feedback"
