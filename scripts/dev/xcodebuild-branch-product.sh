#!/usr/bin/env bash
#
# xcodebuild 래퍼: Voyager-Dev Debug 산출물 이름에 브랜치 suffix 주입.
#
# 순정 xcodebuild 사용자는 기존 Voyager.app 이름을 유지한다.

set -euo pipefail

REAL="${XCODEBUILD_REAL:-/usr/bin/xcodebuild}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HAS_SCHEME_DEV=0
HAS_CONFIG_DEBUG=0
HAS_SUFFIX=0

prev=""
for arg in "$@"; do
  if [[ "$prev" == "-scheme" && "$arg" == "Voyager-Dev" ]]; then
    HAS_SCHEME_DEV=1
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

if [[ "$HAS_SCHEME_DEV" -eq 1 && "$HAS_CONFIG_DEBUG" -eq 1 && "$HAS_SUFFIX" -eq 0 && -n "$BRANCH" ]]; then
  SANITIZED=$(printf '%s' "$BRANCH" | sed -E \
    -e 's/[^A-Za-z0-9._-]/-/g' \
    -e 's/-+/-/g' \
    -e 's/^[-.]+//' \
    -e 's/[-.]+$//')

  if [[ -n "$SANITIZED" ]]; then
    exec "$REAL" "$@" "VOYAGER_APP_SUFFIX=-$SANITIZED"
  fi
fi

exec "$REAL" "$@"
