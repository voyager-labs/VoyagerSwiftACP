#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "usage: lint-and-format-macos.sh <existing-swift-root>" >&2
    exit 2
fi

SWIFT_ROOT="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_ROOT="$REPO_ROOT/apps/macos"

# Probe every required tool before the first formatting mutation.
if ! mise exec -- swiftformat --version >/dev/null 2>&1; then
    echo "BLOCKED: pinned SwiftFormat is unavailable" >&2
    exit 2
fi
if ! mise exec -- swiftlint version >/dev/null 2>&1; then
    echo "BLOCKED: pinned SwiftLint is unavailable" >&2
    exit 2
fi

file_list="$(mktemp)"
trap 'rm -f "$file_list"' EXIT
if ! find "$SWIFT_ROOT" \( -type d -iname build -prune \) -o \
    \( -type d \( -name .build -o -name DerivedData -o -name Pods \) -prune \) -o \
    \( -type f -name '*.swift' -print0 \) > "$file_list"; then
    echo "BLOCKED: Swift source discovery failed" >&2
    exit 2
fi

swift_files=()
while IFS= read -r -d '' file; do
    case "/$file/" in
        */[Bb][Uu][Ii][Ll][Dd]/*|*/.build/*|*/DerivedData/*|*/Pods/*) continue ;;
    esac
    swift_files+=("$file")
done < "$file_list"

if [[ ${#swift_files[@]} -eq 0 ]]; then
    echo "Swift checks: not applicable (no Swift files)"
    exit 0
fi

mise exec -- swiftformat --config "$MACOS_ROOT/.swiftformat" "${swift_files[@]}" --verbose
source_files=()
test_files=()
for file in "${swift_files[@]}"; do
    if [[ "$file" == *Tests/*.swift ]]; then
        test_files+=("$file")
    else
        source_files+=("$file")
    fi
done

lint_status=0
if [[ ${#source_files[@]} -gt 0 ]]; then
    mise exec -- swiftlint --config "$MACOS_ROOT/.swiftlint.yml" --reporter xcode --no-cache "${source_files[@]}" || lint_status=1
fi
if [[ ${#test_files[@]} -gt 0 ]]; then
    mise exec -- swiftlint --config "$MACOS_ROOT/.swiftlint-tests.yml" --reporter xcode --no-cache "${test_files[@]}" || lint_status=1
fi
exit "$lint_status"
