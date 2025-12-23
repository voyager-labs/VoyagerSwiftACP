#!/usr/bin/env bash
# Helper Runtime 준비/번들링을 통합 관리합니다.
# 사용: scripts/build/build-helper-runtime.sh
set -euo pipefail

# Xcode 빌드 로그에서 보이도록 즉시 로그 출력
echo "[VoyagerHelper] Build Helper Runtime script started" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
PROJECT_ROOT="${SRCROOT:-${REPO_ROOT}/apps/macos/Voyager}"
export REPO_ROOT PROJECT_ROOT

MODE_SCRIPT="${SCRIPT_DIR}/handle-backend-mode.sh"
PREPARE_SCRIPT="${SCRIPT_DIR}/prepare-helper-runtime.sh"
BUNDLE_SCRIPT="${SCRIPT_DIR}/bundle-helper-runtime.sh"
SIGN_SCRIPT="${SCRIPT_DIR}/sign-helper-runtime.sh"

BACKEND_MODE="$("${MODE_SCRIPT}" read)"
echo "[VoyagerHelper] Detected BACKEND_MODE=${BACKEND_MODE}" >&2
BACKEND_MODE="${BACKEND_MODE}" "${MODE_SCRIPT}" inject

if [[ "${BACKEND_MODE}" != "bundled" ]]; then
  echo "[VoyagerHelper] BACKEND_MODE=${BACKEND_MODE}: skip Helper Runtime" >&2
  exit 0
fi

echo "[VoyagerHelper] Build Helper Runtime start (mode=${BACKEND_MODE})" >&2

export FORCE_BACKEND_VENV_REBUILD=1
"${PREPARE_SCRIPT}"

VENV_SRC="${VENV_SRC:-${REPO_ROOT}/apps/backend/build/helper-runtime}"
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "[VoyagerHelper] TARGET_BUILD_DIR 또는 UNLOCALIZED_RESOURCES_FOLDER_PATH가 없습니다" >&2
  exit 1
fi
VENV_DST="${VENV_DST:-${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/helper-runtime}"
export VENV_SRC VENV_DST

"${BUNDLE_SCRIPT}"
"${SIGN_SCRIPT}"

echo "[VoyagerHelper] Build Helper Runtime done" >&2
