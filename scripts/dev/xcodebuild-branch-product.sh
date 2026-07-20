#!/usr/bin/env bash
#
# xcodebuild 래퍼: Voyager-Dev Debug 산출물 이름에 브랜치 suffix 주입.
#
# 순정 xcodebuild 사용자는 기존 Voyager.app 이름을 유지한다.

set -euo pipefail

REAL="${XCODEBUILD_REAL:-/usr/bin/xcodebuild}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_RESOLVER="$SCRIPT_DIR/xcodebuild_cache.py"

cd "$REPO_ROOT"

HAS_SCHEME_DEV=0
HAS_CONFIG_DEBUG=0
HAS_SUFFIX=0
SCHEME=""

prev=""
for arg in "$@"; do
  if [[ "$prev" == "-scheme" && "$arg" == "Voyager-Dev" ]]; then
    HAS_SCHEME_DEV=1
  fi
  if [[ "$prev" == "-scheme" ]]; then
    SCHEME="$arg"
  fi
  if [[ "$prev" == "-configuration" && "$arg" == "Debug" ]]; then
    HAS_CONFIG_DEBUG=1
  fi
  if [[ "$arg" == VOYAGER_APP_SUFFIX=* ]]; then
    HAS_SUFFIX=1
  fi
  prev="$arg"
done

BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  BRANCH=""
fi

XCODE_ARGS=("$@")

if [[ "$HAS_SCHEME_DEV" -eq 1 && "$HAS_CONFIG_DEBUG" -eq 1 && "$HAS_SUFFIX" -eq 0 && -n "$BRANCH" ]]; then
  SANITIZED=$(printf '%s' "$BRANCH" | sed -E \
    -e 's/[^A-Za-z0-9._-]/-/g' \
    -e 's/-+/-/g' \
    -e 's/^[-.]+//' \
    -e 's/[-.]+$//')

  if [[ -n "$SANITIZED" ]]; then
    XCODE_ARGS+=("VOYAGER_APP_SUFFIX=-$SANITIZED")
  fi
fi

CACHE_FLAGS_FILE="$(mktemp "${TMPDIR:-/tmp}/voyager-xcode-cache.XXXXXX")" || {
  echo "xcodebuild wrapper: unable to create temporary cache flag file" >&2
  exit 2
}
trap 'rm -f "$CACHE_FLAGS_FILE"' EXIT

if ! python3 "$CACHE_RESOLVER" flags -- "${XCODE_ARGS[@]}" > "$CACHE_FLAGS_FILE"; then
  echo "xcodebuild wrapper: cache flag resolver failed" >&2
  exit 2
fi

CACHE_FLAGS=()
while IFS= read -r -d '' flag; do
  CACHE_FLAGS+=("$flag")
done < "$CACHE_FLAGS_FILE"

if [[ "${#CACHE_FLAGS[@]}" -ne 6 ]]; then
  echo "xcodebuild wrapper: cache flag resolver returned malformed output" >&2
  exit 2
fi
rm -f "$CACHE_FLAGS_FILE"
trap - EXIT

for ((index = 0; index < ${#CACHE_FLAGS[@]}; index += 2)); do
  flag="${CACHE_FLAGS[index]}"
  value="${CACHE_FLAGS[index + 1]}"
  present=0
  for argument in "${XCODE_ARGS[@]}"; do
    if [[ "$argument" == "$flag" || "$argument" == "$flag="* ]]; then
      present=1
      break
    fi
  done
  if [[ "$present" -eq 0 ]]; then
    XCODE_ARGS+=("$flag" "$value")
  fi
done

ENTRYPOINT="${VOYAGER_XCODE_CACHE_ENTRYPOINT:-${SCHEME:-xcodebuild-wrapper}}"
exec env VOYAGER_XCODE_CACHE_ENTRYPOINT="$ENTRYPOINT" python3 "$CACHE_RESOLVER" exec -- "$REAL" "${XCODE_ARGS[@]}"
