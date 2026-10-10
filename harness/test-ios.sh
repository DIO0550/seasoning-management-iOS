#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash harness/test-ios.sh <SeasoningManagerTests|SeasoningManagerUITests|all> <destination>"
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

target="$1"
destination="$2"
case "$target" in
  SeasoningManagerTests|SeasoningManagerUITests)
    ;;
  all)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ -z "$destination" ]]; then
  usage >&2
  exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "iOS tests not run: Xcode is required. Use the Mac CI or a Mac with the project's Xcode." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

test_command=(xcodebuild test \
  -project src/SeasoningManager/SeasoningManager.xcodeproj \
  -scheme SeasoningManager \
  -configuration Debug \
  -destination "$destination" \
  -destination-timeout 120 \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO)

if [[ "$target" != "all" ]]; then
  test_command+=("-only-testing:$target")
fi

# CI supplies a unique path per matrix job; local calls keep their existing behavior.
if [[ -n "${HARNESS_RESULT_BUNDLE:-}" ]]; then
  test_command+=(-resultBundlePath "$HARNESS_RESULT_BUNDLE" -enableCodeCoverage YES)
fi

exec "${test_command[@]}"
