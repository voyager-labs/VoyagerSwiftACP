#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: lint-and-format-macos.sh <swift-root>" >&2
    exit 2
fi

SWIFT_ROOT="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_ROOT="$REPO_ROOT/apps/macos"

echo "================================"
echo "🔍 SwiftLint: using system installation..."
echo "================================"

if command -v swiftlint >/dev/null 2>&1; then
    echo "✓ Running SwiftLint at: $(which swiftlint)"

    source_files=()
    test_files=()

    # 테스트 디렉터리는 길이 metric과 테스트 이름 규칙을 제외한 별도 config로 lint합니다.
    while IFS= read -r -d '' file; do
        if [[ "$file" == *Tests/*.swift ]]; then
            test_files+=("$file")
        else
            source_files+=("$file")
        fi
    done < <(find "$SWIFT_ROOT" -name '*.swift' -print0)

    if [[ ${#source_files[@]} -gt 0 ]]; then
        swiftlint --config "$MACOS_ROOT/.swiftlint.yml" --reporter xcode "${source_files[@]}"
    fi

    if [[ ${#test_files[@]} -gt 0 ]]; then
        swiftlint --config "$MACOS_ROOT/.swiftlint-tests.yml" --reporter xcode "${test_files[@]}"
    fi

    echo "✓ SwiftLint completed"
else
    echo "⚠️ SwiftLint not found in PATH"
fi

echo "================================"
echo "🔧 SwiftFormat: using system installation..."
echo "================================"

if command -v swiftformat >/dev/null 2>&1; then
    echo "✓ Running SwiftFormat at: $(which swiftformat)"
    swiftformat --config "$MACOS_ROOT/.swiftformat" "$SWIFT_ROOT" --verbose || true
    echo "✓ SwiftFormat completed"
else
    echo "⚠️ SwiftFormat not found in PATH"
fi

echo "================================"
