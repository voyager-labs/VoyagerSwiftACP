#!/usr/bin/env bash
# Shared macOS test command for human/CI use.
# Agent verification uses XcodeBuildMCP, NOT this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ "${1:-}" == "--dry-run" ]]; then
    shift
    echo "NSUnbufferedIO=YES xcodebuild test \\"
    echo "  -project apps/macos/Voyager/Voyager.xcodeproj \\"
    echo "  -scheme Voyager-Dev \\"
    echo "  -configuration Debug \\"
    echo "  -derivedDataPath build/dev/DerivedData \\"
    echo "  -clonedSourcePackagesDirPath build/dev/SourcePackages \\"
    echo "  -skipPackagePluginValidation \\"
    echo "  -skipMacroValidation \\"
    echo "  COMPILER_INDEX_STORE_ENABLE=NO \\"
    echo "  CODE_SIGNING_ALLOWED=NO \\"
    if [[ $# -gt 0 ]]; then
        printf '  '
        printf '%q ' "$@"
        printf '\\\n'
    fi
    echo "  2>&1 | tee build/dev/xcodebuild-test.log | xcbeautify --quiet --is-ci --report junit --report-path build/dev/reports"
    exit 0
fi

mkdir -p "$REPO_ROOT/build/dev/reports"

NSUnbufferedIO=YES xcodebuild test \
    -project "$REPO_ROOT/apps/macos/Voyager/Voyager.xcodeproj" \
    -scheme Voyager-Dev \
    -configuration Debug \
    -derivedDataPath "$REPO_ROOT/build/dev/DerivedData" \
    -clonedSourcePackagesDirPath "$REPO_ROOT/build/dev/SourcePackages" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    COMPILER_INDEX_STORE_ENABLE=NO \
    CODE_SIGNING_ALLOWED=NO \
    "$@" \
    2>&1 | tee "$REPO_ROOT/build/dev/xcodebuild-test.log" | mise exec -- xcbeautify --quiet --is-ci --report junit --report-path "$REPO_ROOT/build/dev/reports"
