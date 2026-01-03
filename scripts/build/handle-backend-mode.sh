#!/usr/bin/env bash
# BACKEND_MODE 읽기/주입을 분리 관리합니다.
# 사용: scripts/build/handle-backend-mode.sh <read|inject>
set -euo pipefail

ACTION="${1:-}"
if [[ "${ACTION}" != "read" && "${ACTION}" != "inject" ]]; then
  echo "Usage: $0 <read|inject>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
PROJECT_ROOT="${PROJECT_ROOT:-${SRCROOT:-${REPO_ROOT}/apps/macos/Voyager}}"

read_backend_mode() {
  local mode_file="${PROJECT_ROOT}/VoyagerHelper/.backend_mode"
  local mode
  if [[ -f "${mode_file}" ]]; then
    mode="$(tr -d ' \t\r\n' < "${mode_file}")"
    echo "[VoyagerHelper] Read BACKEND_MODE=${mode} from Pre-action" >&2
  else
    mode="source"
    echo "[VoyagerHelper] .backend_mode not found, using default: ${mode}" >&2
  fi
  printf "%s" "${mode}"
}

if [[ "${ACTION}" == "read" ]]; then
  read_backend_mode
  exit 0
fi

BACKEND_MODE="${BACKEND_MODE:-$(read_backend_mode)}"
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${INFOPLIST_PATH:-}" ]]; then
  exit 0
fi

bundle_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [[ -f "${bundle_plist}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :BACKEND_MODE ${BACKEND_MODE}" "${bundle_plist}" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :BACKEND_MODE string ${BACKEND_MODE}" "${bundle_plist}"
  echo "[VoyagerHelper] Injected BACKEND_MODE=${BACKEND_MODE} into ${bundle_plist}" >&2
fi
