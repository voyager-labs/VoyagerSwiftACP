#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-${PWD}/build/ci}"
PROJECT_PATH="${PROJECT_PATH:-}"
SCHEME="${SCHEME:-}"
CONFIGURATION="${CONFIGURATION:-Release}"
CURRENT_PROJECT_VERSION_OVERRIDE="${CURRENT_PROJECT_VERSION_OVERRIDE:-}"
VOYAGER_RELEASED_AT="${VOYAGER_RELEASED_AT:-}"

if [[ -z "${PROJECT_PATH}" || -z "${SCHEME}" ]]; then
  echo "Missing PROJECT_PATH or SCHEME." >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${BUILD_DIR}/Voyager.xcarchive" \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  -clonedSourcePackagesDirPath "${BUILD_DIR}/SourcePackages" \
  ${CURRENT_PROJECT_VERSION_OVERRIDE:+CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION_OVERRIDE}} \
  ${VOYAGER_RELEASED_AT:+VOYAGER_RELEASED_AT=${VOYAGER_RELEASED_AT}} \
  archive
