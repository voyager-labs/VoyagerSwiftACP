#!/usr/bin/env bash
# Release/bundled에서 번들 리소스에 환경 파일을 복사합니다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
  echo "[Voyager] Skip env copy for ${CONFIGURATION:-unknown}" >&2
  exit 0
fi

MODE_SCRIPT="${REPO_ROOT}/scripts/build/handle-backend-mode.sh"
BACKEND_MODE="$("${MODE_SCRIPT}" read)"
if [[ "${BACKEND_MODE}" != "bundled" ]]; then
  echo "[Voyager] BACKEND_MODE=${BACKEND_MODE}: skip env copy" >&2
  exit 0
fi

DEST_DIR="${1:-}"
if [[ -z "${DEST_DIR}" ]]; then
  if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
    echo "[Voyager] TARGET_BUILD_DIR 또는 UNLOCALIZED_RESOURCES_FOLDER_PATH가 없습니다" >&2
    exit 0
  fi
  DEST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
fi

if [[ ! -d "${DEST_DIR}" ]]; then
  echo "[Voyager] Resource dir missing: ${DEST_DIR}" >&2
  exit 0
fi

ENV_BUNDLED_SRC="${REPO_ROOT}/.env.bundled"
ENV_PROD_SRC="${REPO_ROOT}/.env.prod"

if [[ -f "${ENV_BUNDLED_SRC}" ]]; then
  cp "${ENV_BUNDLED_SRC}" "${DEST_DIR}/.env.bundled"
  echo "[Voyager] .env.bundled 복사 완료: ${DEST_DIR}/.env.bundled" >&2
else
  echo "[Voyager] .env.bundled not found: ${ENV_BUNDLED_SRC}" >&2
fi

if [[ -f "${ENV_PROD_SRC}" ]]; then
  cp "${ENV_PROD_SRC}" "${DEST_DIR}/.env.prod"
  echo "[Voyager] .env.prod 복사 완료: ${DEST_DIR}/.env.prod" >&2
else
  echo "[Voyager] .env.prod not found: ${ENV_PROD_SRC}" >&2
fi
