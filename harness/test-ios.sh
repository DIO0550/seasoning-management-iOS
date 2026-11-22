#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash harness/test-ios.sh <SeasoningManagerTests|SeasoningManagerUITests|<target>/<class>[/<test>]|all>[,...] <destination>"
  echo "Optional: HARNESS_XCODE_ACTION=test (default)|build-for-testing|test-without-building"
  echo "  build-for-testing: target all and HARNESS_DERIVED_DATA are required."
  echo "  test-without-building: HARNESS_XCTESTRUN must be an existing .xctestrun file."
  echo "  HARNESS_SKIP_TESTING=<target>/<class>[/<test>][,...] skips tests (not for build-for-testing)."
}

fail_usage() {
  if [[ -n "${1:-}" ]]; then
    echo "$1" >&2
  fi
  usage >&2
  exit 2
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  fail_usage
fi

target="$1"
destination="$2"
action="${HARNESS_XCODE_ACTION:-test}"
derived_data="${HARNESS_DERIVED_DATA:-}"
xctestrun="${HARNESS_XCTESTRUN:-}"
skip_list="${HARNESS_SKIP_TESTING:-}"
result_bundle="${HARNESS_RESULT_BUNDLE:-}"

# カンマ区切りを空要素も残して分割する（macOS 標準の bash 3.2 でも動く書き方）。
only_testing=()
if [[ "$target" != "all" ]]; then
  rest="$target,"
  while [[ -n "$rest" ]]; do
    only_testing+=("${rest%%,*}")
    rest="${rest#*,}"
  done
  for item in "${only_testing[@]}"; do
    case "$item" in
      SeasoningManagerTests|SeasoningManagerUITests|SeasoningManagerTests/?*|SeasoningManagerUITests/?*)
        ;;
      *)
        # all は単独でのみ指定できる。空要素や未知の対象も止める。
        fail_usage "Invalid test target: '$item'"
        ;;
    esac
  done
fi

skip_testing=()
if [[ -n "$skip_list" ]]; then
  rest="$skip_list,"
  while [[ -n "$rest" ]]; do
    skip_testing+=("${rest%%,*}")
    rest="${rest#*,}"
  done
  for item in "${skip_testing[@]}"; do
    case "$item" in
      SeasoningManagerTests/?*|SeasoningManagerUITests/?*)
        ;;
      *)
        fail_usage "Invalid HARNESS_SKIP_TESTING entry: '$item'"
        ;;
    esac
  done
fi

if [[ -z "$destination" ]]; then
  fail_usage
fi

case "$action" in
  test)
    if [[ -n "$derived_data" || -n "$xctestrun" ]]; then
      fail_usage "HARNESS_DERIVED_DATA and HARNESS_XCTESTRUN are only for build-for-testing / test-without-building."
    fi
    ;;
  build-for-testing)
    if [[ "$target" != "all" ]]; then
      fail_usage "build-for-testing builds every test target; use all."
    fi
    if [[ -z "$derived_data" ]]; then
      fail_usage "build-for-testing requires HARNESS_DERIVED_DATA."
    fi
    if [[ -n "$xctestrun" || -n "$skip_list" || -n "$result_bundle" ]]; then
      fail_usage "build-for-testing runs no tests; unset HARNESS_XCTESTRUN, HARNESS_SKIP_TESTING, and HARNESS_RESULT_BUNDLE."
    fi
    ;;
  test-without-building)
    if [[ -z "$xctestrun" || ! -f "$xctestrun" ]]; then
      fail_usage "test-without-building requires HARNESS_XCTESTRUN to be an existing .xctestrun file."
    fi
    if [[ -n "$derived_data" ]]; then
      fail_usage "test-without-building does not build; unset HARNESS_DERIVED_DATA."
    fi
    ;;
  *)
    fail_usage "Invalid HARNESS_XCODE_ACTION: '$action'"
    ;;
esac

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "iOS tests not run: Xcode is required. Use the Mac CI or a Mac with the project's Xcode." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 相対パスの xctestrun は呼び出し元の位置で解決してからリポジトリへ移動する。
if [[ -n "$xctestrun" ]]; then
  xctestrun="$(cd "$(dirname "$xctestrun")" && pwd)/$(basename "$xctestrun")"
fi
cd "$repo_root"

if [[ "$action" == "build-for-testing" ]]; then
  # CI はここで1回だけビルドし、各テストジョブは test-without-building で成果物を使う。
  exec xcodebuild build-for-testing \
    -project src/SeasoningManager/SeasoningManager.xcodeproj \
    -scheme SeasoningManager \
    -configuration Debug \
    -destination "$destination" \
    -destination-timeout 120 \
    -derivedDataPath "$derived_data" \
    -enableCodeCoverage YES \
    CODE_SIGNING_ALLOWED=NO
fi

if [[ "$action" == "test-without-building" ]]; then
  # 構成と署名はビルド済みの xctestrun に含まれるため、プロジェクトやスキームは渡さない。
  test_command=(xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "$destination" \
    -destination-timeout 120 \
    -retry-tests-on-failure)
else
  test_command=(xcodebuild test \
    -project src/SeasoningManager/SeasoningManager.xcodeproj \
    -scheme SeasoningManager \
    -configuration Debug \
    -destination "$destination" \
    -destination-timeout 120 \
    # 混んだランナーで出るスナップショット評価タイムアウトを再試行で吸収する。
    -retry-tests-on-failure \
    CODE_SIGNING_ALLOWED=NO)
fi

# クローン並列は小さい CI ランナーでは CPU を分けて遅くなるため、CI は NO で直列にする。
if [[ "${HARNESS_PARALLEL_TESTS:-YES}" == "YES" ]]; then
  test_command+=(-parallel-testing-enabled YES -parallel-testing-worker-count 2)
else
  test_command+=(-parallel-testing-enabled NO)
fi

# bash 3.2 の set -u では空配列の展開がエラーになるため、要素があるときだけ展開する。
for item in ${only_testing[@]+"${only_testing[@]}"}; do
  test_command+=("-only-testing:$item")
done

for item in ${skip_testing[@]+"${skip_testing[@]}"}; do
  test_command+=("-skip-testing:$item")
done

# CI supplies a unique path per matrix job; local calls keep their existing behavior.
if [[ -n "$result_bundle" ]]; then
  test_command+=(-resultBundlePath "$result_bundle" -enableCodeCoverage YES)
fi

exec "${test_command[@]}"
