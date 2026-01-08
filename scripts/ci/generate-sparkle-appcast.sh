#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-${PWD}/build/ci}"
VERSION="${VERSION:-}"
DOWNLOADS_BASE_URL="${DOWNLOADS_BASE_URL:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SPARKLE_BIN="${SPARKLE_BIN:-${BUILD_DIR}/SourcePackages/artifacts/sparkle/Sparkle/bin}"

if [[ -z "${DOWNLOADS_BASE_URL}" ]]; then
  echo "Missing DOWNLOADS_BASE_URL." >&2
  exit 1
fi
if [[ -z "${VERSION}" ]]; then
  echo "Missing VERSION." >&2
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY}" ]]; then
  echo "Missing SPARKLE_PRIVATE_KEY." >&2
  exit 1
fi

DOWNLOADS_BASE_URL="${DOWNLOADS_BASE_URL%/}"
APPCAST_PATH="${BUILD_DIR}/appcast.xml"
SPARKLE_WORK_DIR="${BUILD_DIR}/.sparkle"
BASELINE_ROOT="${BUILD_DIR}/baseline"
CURRENT_ZIP="${BUILD_DIR}/Voyager-${VERSION}.zip"
DOWNLOAD_PREFIX="${DOWNLOADS_BASE_URL}/releases/versions"

if [[ ! -x "${SPARKLE_BIN}/generate_appcast" ]]; then
  SPARKLE_BIN_PATH="$(
    find "${BUILD_DIR}/DerivedData" "${BUILD_DIR}/SourcePackages" \
      -type f -name generate_appcast -print -quit 2>/dev/null || true
  )"
  if [[ -n "${SPARKLE_BIN_PATH}" ]]; then
    SPARKLE_BIN="$(dirname "${SPARKLE_BIN_PATH}")"
  fi
fi

if [[ ! -x "${SPARKLE_BIN}/generate_appcast" ]]; then
  echo "generate_appcast not found." >&2
  exit 1
fi

rm -rf "${SPARKLE_WORK_DIR}"
mkdir -p "${SPARKLE_WORK_DIR}"
trap 'rm -rf "${SPARKLE_WORK_DIR}"' EXIT
if [[ -f "${APPCAST_PATH}" ]]; then
  cp "${APPCAST_PATH}" "${SPARKLE_WORK_DIR}/appcast.xml"
fi
if [[ -d "${BASELINE_ROOT}" ]]; then
  while IFS= read -r zip_path; do
    [[ -z "${zip_path}" ]] && continue
    cp "${zip_path}" "${SPARKLE_WORK_DIR}/"
  done < <(find "${BASELINE_ROOT}" -maxdepth 1 -type f -name "Voyager-*.zip" 2>/dev/null || true)
fi

if [[ ! -f "${CURRENT_ZIP}" ]]; then
  echo "Missing current Sparkle zip: ${CURRENT_ZIP}" >&2
  exit 1
fi
cp "${CURRENT_ZIP}" "${SPARKLE_WORK_DIR}/"

printf "%s" "${SPARKLE_PRIVATE_KEY}" | "${SPARKLE_BIN}/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "${DOWNLOAD_PREFIX}" \
  "${SPARKLE_WORK_DIR}"

python3 - "${SPARKLE_WORK_DIR}/appcast.xml" "${DOWNLOAD_PREFIX}" <<'PY'
import re
import sys

appcast_path = sys.argv[1]
download_prefix = sys.argv[2].rstrip("/")

with open(appcast_path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(re.escape(download_prefix) + r"/Voyager-([^/\"]+)\.zip")

def rewrite(match: re.Match[str]) -> str:
    version = match.group(1)
    return f"{download_prefix}/{version}/Voyager-{version}.zip"

content = pattern.sub(rewrite, content)

with open(appcast_path, "w", encoding="utf-8") as f:
    f.write(content)
PY

if [[ -f "${SPARKLE_WORK_DIR}/appcast.xml" && "${APPCAST_PATH}" != "${SPARKLE_WORK_DIR}/appcast.xml" ]]; then
  mkdir -p "$(dirname "${APPCAST_PATH}")"
  mv "${SPARKLE_WORK_DIR}/appcast.xml" "${APPCAST_PATH}"
fi

rm -rf "${SPARKLE_WORK_DIR}"
trap - EXIT
