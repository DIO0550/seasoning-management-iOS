#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# PostToolUse input is intentionally not used to interpret a command or file path.
# Validate the current harness after Edit/Write, without changing any files.
if ! python3 "$repo_root/harness/check.py"; then
  echo "Harness configuration is inconsistent. Fix the references/settings before continuing." >&2
  exit 2
fi
