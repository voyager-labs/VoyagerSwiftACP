#!/usr/bin/env bash
# Helper Runtime 번들링(복사 및 .env.prod 준비)을 분리 관리합니다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

VENV_SRC="${VENV_SRC:-${REPO_ROOT}/apps/backend/build/helper-runtime}"
if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "TARGET_BUILD_DIR 또는 UNLOCALIZED_RESOURCES_FOLDER_PATH가 없습니다" >&2
  exit 1
fi
VENV_DST="${VENV_DST:-${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/helper-runtime}"

if [[ ! -x "${VENV_SRC}/bin/python" ]]; then
  echo "helper-runtime가 없습니다: ${VENV_SRC}/bin/python" >&2
  exit 1
fi

if [[ -d "${VENV_DST}" ]]; then
  chmod -R u+w "${VENV_DST}" 2>/dev/null || true
  rm -rf "${VENV_DST}" || true
fi
mkdir -p "$(dirname "${VENV_DST}")"
ditto "${VENV_SRC}" "${VENV_DST}"

ENV_PROD_SRC="${ENV_PROD_SRC:-${REPO_ROOT}/.env.prod}"
ENV_PROD_DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/.env.prod"
mkdir -p "$(dirname "${ENV_PROD_DST}")"
if [[ -f "${ENV_PROD_SRC}" ]]; then
  cp "${ENV_PROD_SRC}" "${ENV_PROD_DST}"
  echo "Copied .env.prod to bundle: ${ENV_PROD_DST}"
else
  echo "Error: .env.prod not found at ${ENV_PROD_SRC}" >&2
  exit 1
fi
