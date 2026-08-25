#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: lint-and-format-macos.sh <swift-root>" >&2
    exit 2
fi

SWIFT_ROOT="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_ROOT="$REPO_ROOT/apps/macos"

swift_files=()
while IFS= read -r -d '' file; do
    case "/$file/" in
        */[Bb][Uu][Ii][Ll][Dd]/*) continue ;;
    esac
    swift_files+=("$file")
done < <(find "$SWIFT_ROOT" \( -type d -iname build -prune \) -o \( -type f -name '*.swift' -print0 \))

echo "================================"
echo "🔧 SwiftFormat: using mise-managed installation..."
echo "================================"

if mise exec -- swiftformat --version >/dev/null 2>&1; then
    echo "✓ Running SwiftFormat via mise"
    if [[ ${#swift_files[@]} -gt 0 ]]; then
        mise exec -- swiftformat --config "$MACOS_ROOT/.swiftformat" "${swift_files[@]}" --verbose
        echo "✓ SwiftFormat completed"
    else
        echo "✓ SwiftFormat skipped (no Swift files found)"
    fi
else
    echo "⚠️ SwiftFormat not found via mise"
fi

echo "================================"
echo "🔍 SwiftLint: using mise-managed installation..."
echo "================================"

lint_status=0

if mise exec -- swiftlint version >/dev/null 2>&1; then
    echo "✓ Running SwiftLint via mise"

    source_files=()
    test_files=()

    # 테스트 디렉터리는 길이 metric과 테스트 이름 규칙을 제외한 별도 config로 lint합니다.
    if [[ ${#swift_files[@]} -gt 0 ]]; then
        for file in "${swift_files[@]}"; do
            if [[ "$file" == *Tests/*.swift ]]; then
                test_files+=("$file")
            else
                source_files+=("$file")
            fi
        done
    fi

    if [[ ${#source_files[@]} -gt 0 ]]; then
        if ! mise exec -- swiftlint --config "$MACOS_ROOT/.swiftlint.yml" --reporter xcode --no-cache "${source_files[@]}"; then
            lint_status=1
        fi
    fi

    if [[ ${#test_files[@]} -gt 0 ]]; then
        if ! mise exec -- swiftlint --config "$MACOS_ROOT/.swiftlint-tests.yml" --reporter xcode --no-cache "${test_files[@]}"; then
            lint_status=1
        fi
    fi

    if [[ "$lint_status" -eq 0 ]]; then
        echo "✓ SwiftLint completed"
    else
        echo "✗ SwiftLint completed with failures"
    fi
else
    echo "⚠️ SwiftLint not found via mise"
fi

echo "================================"

exit "$lint_status"
