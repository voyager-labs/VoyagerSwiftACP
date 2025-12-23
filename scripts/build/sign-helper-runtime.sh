#!/usr/bin/env bash
# Helper Runtime 바이너리 코드사인 단계를 분리 관리합니다.
set -euo pipefail

if [[ -z "${VENV_DST:-}" ]]; then
  if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
    echo "VENV_DST 또는 TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH가 없습니다" >&2
    exit 1
  fi
  VENV_DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/helper-runtime"
fi

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "Signing helper-runtime binaries with ${SIGN_IDENTITY}"
  find "${VENV_DST}" -type f -print0 | while IFS= read -r -d '' candidate; do
    if /usr/bin/file "${candidate}" | /usr/bin/grep -q "Mach-O"; then
      /usr/bin/codesign --force --sign "${SIGN_IDENTITY}" "${candidate}"
    fi
  done
else
  echo "Warning: EXPANDED_CODE_SIGN_IDENTITY not set; skip helper-runtime signing" >&2
fi
