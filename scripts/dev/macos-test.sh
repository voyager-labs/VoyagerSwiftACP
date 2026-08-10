#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
XCODEBUILD_CMD="${XCODEBUILD_CMD:-"$SCRIPT_DIR/xcodebuild-branch-product.sh"}"

DRY_RUN=0
SCHEME="Voyager-Dev"
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --scheme)
            if [[ $# -lt 2 ]]; then
                echo "macos-test: --scheme requires a value" >&2
                exit 2
            fi
            SCHEME="$2"
            shift 2
            ;;
        *)
            PASSTHROUGH_ARGS+=("$1")
            shift
            ;;
    esac
done

case "$SCHEME" in
    Voyager-Dev)
        ARTIFACT_KEY="voyager-dev"
        ;;
    Voyager-Lifecycle-Smoke)
        ARTIFACT_KEY="voyager-lifecycle-smoke"
        ;;
    VoyagerHelper-Dev)
        ARTIFACT_KEY="voyager-helper-dev"
        ;;
    *)
        echo "macos-test: unsupported scheme: $SCHEME" >&2
        exit 2
        ;;
esac

LOG_RELATIVE="build/dev/xcodebuild-test-$ARTIFACT_KEY.log"
REPORT_RELATIVE="build/dev/reports/$ARTIFACT_KEY"
LOG_PATH="$REPO_ROOT/$LOG_RELATIVE"
REPORT_PATH="$REPO_ROOT/$REPORT_RELATIVE"

if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' \
        'NSUnbufferedIO=YES scripts/dev/xcodebuild-branch-product.sh test \' \
        '  -project apps/macos/Voyager/Voyager.xcodeproj \' \
        "  -scheme $SCHEME \\" \
        '  -configuration Dev-Debug \' \
        '  -skipPackagePluginValidation \' \
        '  -skipMacroValidation \' \
        '  COMPILER_INDEX_STORE_ENABLE=NO \' \
        '  CODE_SIGNING_ALLOWED=NO \'
    if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
        printf '  '
        printf '%q ' "${PASSTHROUGH_ARGS[@]}"
        printf '\\\n'
    fi
    echo "  2>&1 | tee $LOG_RELATIVE | xcbeautify --quiet --is-ci --report junit --report-path $REPORT_RELATIVE"
    exit 0
fi

mkdir -p "$REPORT_PATH"

XCODE_ARGS=(
    test
    -project "$REPO_ROOT/apps/macos/Voyager/Voyager.xcodeproj"
    -scheme "$SCHEME"
    -configuration Dev-Debug
    -skipPackagePluginValidation
    -skipMacroValidation
    COMPILER_INDEX_STORE_ENABLE=NO
    CODE_SIGNING_ALLOWED=NO
)
if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
    XCODE_ARGS+=("${PASSTHROUGH_ARGS[@]}")
fi

NSUnbufferedIO=YES "$XCODEBUILD_CMD" "${XCODE_ARGS[@]}" \
    2>&1 | tee "$LOG_PATH" | mise exec -- xcbeautify --quiet --is-ci --report junit --report-path "$REPORT_PATH"
