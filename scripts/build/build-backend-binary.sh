#!/usr/bin/env bash
# Backend Nuitka Binary 준비/빌드/번들링을 통합 관리합니다.
# 사용: scripts/build/build-backend-binary.sh
set -euo pipefail

echo "[VoyagerHelper] Build Backend Binary script started" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
PROJECT_ROOT="${SRCROOT:-${REPO_ROOT}/apps/macos/Voyager}"
export REPO_ROOT PROJECT_ROOT

MODE_SCRIPT="${SCRIPT_DIR}/handle-backend-mode.sh"
PREPARE_SCRIPT="${SCRIPT_DIR}/prepare-helper-runtime.sh"
COMPILE_SCRIPT="${SCRIPT_DIR}/compile-nuitka-binary.sh"

# BACKEND_MODE 읽기
BACKEND_MODE="$("${MODE_SCRIPT}" read)"
echo "[VoyagerHelper] Detected BACKEND_MODE=${BACKEND_MODE}" >&2

if [[ "${BACKEND_MODE}" != "bundled" ]]; then
  echo "[VoyagerHelper] BACKEND_MODE=${BACKEND_MODE}: skip Backend Binary" >&2
  exit 0
fi

# BACKEND_MODE를 Info.plist에 주입
BACKEND_MODE="${BACKEND_MODE}" "${MODE_SCRIPT}" inject

echo "[VoyagerHelper] Build Backend Binary start (mode=${BACKEND_MODE})" >&2

# 개발 중 스킵 옵션 (환경 변수로 제어)
SKIP_NUITKA_BUILD="${SKIP_NUITKA_BUILD:-0}"
if [[ "${SKIP_NUITKA_BUILD}" == "1" ]]; then
  echo "[VoyagerHelper] SKIP_NUITKA_BUILD=1: Nuitka 빌드 스킵" >&2
  echo "[VoyagerHelper] 기존 바이너리 사용 (있는 경우)" >&2
else
  # 1. venv 준비
  "${PREPARE_SCRIPT}"

  # 2. Nuitka 컴파일 (증분 빌드 지원)
  "${COMPILE_SCRIPT}"
fi

# 3. 바이너리 번들링 (앱 번들에 복사)
NUITKA_DIST="${REPO_ROOT}/apps/backend/build/nuitka/server.dist"
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "[VoyagerHelper] TARGET_BUILD_DIR 또는 UNLOCALIZED_RESOURCES_FOLDER_PATH가 없습니다" >&2
  exit 1
fi
BINARY_DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/server"

if [[ ! -d "${NUITKA_DIST}" ]]; then
  echo "[VoyagerHelper] Nuitka 빌드 결과를 찾을 수 없습니다: ${NUITKA_DIST}" >&2
  exit 1
fi

echo "[VoyagerHelper] 바이너리 번들링: ${NUITKA_DIST} -> ${BINARY_DST}" >&2
if [[ -d "${BINARY_DST}" ]]; then
  chmod -R u+w "${BINARY_DST}" 2>/dev/null || true
  rm -rf "${BINARY_DST}" || true
fi
mkdir -p "$(dirname "${BINARY_DST}")"
ditto "${NUITKA_DIST}" "${BINARY_DST}"

# .env.prod 복사
ENV_PROD_SRC="${REPO_ROOT}/.env.prod"
ENV_PROD_DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/.env.prod"
if [[ -f "${ENV_PROD_SRC}" ]]; then
  cp "${ENV_PROD_SRC}" "${ENV_PROD_DST}"
  echo "[VoyagerHelper] .env.prod 복사 완료: ${ENV_PROD_DST}" >&2
else
  echo "[VoyagerHelper] 경고: .env.prod를 찾을 수 없습니다: ${ENV_PROD_SRC}" >&2
fi

# 4. 바이너리 서명
SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -n "${SIGN_IDENTITY}" && "${SIGN_IDENTITY}" != "-" ]]; then
  echo "[VoyagerHelper] 바이너리 서명 중 (identity: ${SIGN_IDENTITY})" >&2
  find "${BINARY_DST}" -type f -print0 | while IFS= read -r -d '' candidate; do
    if /usr/bin/file "${candidate}" | /usr/bin/grep -q "Mach-O"; then
      /usr/bin/codesign \
        --force \
        --sign "${SIGN_IDENTITY}" \
        --options runtime \
        --timestamp \
        "${candidate}"
    fi
  done
  echo "[VoyagerHelper] 바이너리 서명 완료" >&2
else
  echo "[VoyagerHelper] 경고: EXPANDED_CODE_SIGN_IDENTITY가 없습니다. 서명 생략" >&2
fi

echo "[VoyagerHelper] Build Backend Binary done" >&2
