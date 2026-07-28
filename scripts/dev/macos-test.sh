#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
XCODEBUILD_CMD="${XCODEBUILD_CMD:-"$SCRIPT_DIR/xcodebuild-branch-product.sh"}"

if [[ "${1:-}" == "--dry-run" ]]; then
    shift
    printf '%s\n' \
        'NSUnbufferedIO=YES scripts/dev/xcodebuild-branch-product.sh test \' \
        '  -project apps/macos/Voyager/Voyager.xcodeproj \' \
        '  -scheme Voyager-Dev \' \
        '  -configuration Dev-Debug \' \
        '  -skipPackagePluginValidation \' \
        '  -skipMacroValidation \' \
        '  COMPILER_INDEX_STORE_ENABLE=NO \' \
        '  CODE_SIGNING_ALLOWED=NO \'
    if [[ $# -gt 0 ]]; then
        printf '  '
        printf '%q ' "$@"
        printf '\\\n'
    fi
    echo "  2>&1 | tee build/dev/xcodebuild-test.log | xcbeautify --quiet --is-ci --report junit --report-path build/dev/reports"
    exit 0
fi

mkdir -p "$REPO_ROOT/build/dev/reports"

NSUnbufferedIO=YES "$XCODEBUILD_CMD" test \
    -project "$REPO_ROOT/apps/macos/Voyager/Voyager.xcodeproj" \
    -scheme Voyager-Dev \
    -configuration Dev-Debug \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    COMPILER_INDEX_STORE_ENABLE=NO \
    CODE_SIGNING_ALLOWED=NO \
    "$@" \
    2>&1 | tee "$REPO_ROOT/build/dev/xcodebuild-test.log" | mise exec -- xcbeautify --quiet --is-ci --report junit --report-path "$REPO_ROOT/build/dev/reports"
