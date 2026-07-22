#!/usr/bin/env bash
# Release/bundled에서 번들 리소스에 환경 파일을 복사합니다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

if [[ "${APP_ENV:-}" != "prod" ]]; then
  echo "[Voyager] Skip env copy for APP_ENV=${APP_ENV:-unset}" >&2
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

ENV_PROD_SRC="${REPO_ROOT}/.env.prod"

if [[ -f "${ENV_PROD_SRC}" ]]; then
  cp "${ENV_PROD_SRC}" "${DEST_DIR}/.env.prod"
  echo "[Voyager] .env.prod 복사 완료: ${DEST_DIR}/.env.prod" >&2
else
  echo "[Voyager] .env.prod not found: ${ENV_PROD_SRC}" >&2
fi
