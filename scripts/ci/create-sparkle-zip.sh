#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-${PWD}/build/ci}"
VERSION="${VERSION:-}"
APP_PATH="${APP_PATH:-${BUILD_DIR}/export/Voyager.app}"

if [[ -z "${VERSION}" ]]; then
  echo "Missing VERSION." >&2
  exit 1
fi
if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found at ${APP_PATH}." >&2
  exit 1
fi

ZIP_PATH="${BUILD_DIR}/Voyager-${VERSION}.zip"

mkdir -p "$(dirname "${ZIP_PATH}")"
ditto -c -k --zlibCompressionLevel 9 --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
