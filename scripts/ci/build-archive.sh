#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-${PWD}/build/ci}"
PROJECT_PATH="${PROJECT_PATH:-}"
SCHEME="${SCHEME:-}"
CONFIGURATION="${CONFIGURATION:-Release}"

if [[ -z "${PROJECT_PATH}" || -z "${SCHEME}" ]]; then
  echo "Missing PROJECT_PATH or SCHEME." >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"

ENV_PROD_PATH="${BUILD_DIR}/.env.prod"
./scripts/ci/write-env-prod.sh "${ENV_PROD_PATH}"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${BUILD_DIR}/Voyager.xcarchive" \
  ENV_PROD_SRC="${ENV_PROD_PATH}" \
  archive

