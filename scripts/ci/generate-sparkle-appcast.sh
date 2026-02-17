#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-${PWD}/build/ci}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${VERSION:-}"
DOWNLOADS_BASE_URL="${DOWNLOADS_BASE_URL:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SPARKLE_BIN="${SPARKLE_BIN:-${BUILD_DIR}/SourcePackages/artifacts/sparkle/Sparkle/bin}"
SPARKLE_BASELINE_COUNT="${SPARKLE_BASELINE_COUNT:-}"
SPARKLE_MAXIMUM_DELTAS="${SPARKLE_MAXIMUM_DELTAS:-0}"

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
if [[ -n "${SPARKLE_BASELINE_COUNT}" ]]; then
  if ! [[ "${SPARKLE_BASELINE_COUNT}" =~ ^[0-9]+$ ]]; then
    echo "SPARKLE_BASELINE_COUNT must be an integer." >&2
    exit 1
  fi
fi
DOWNLOADS_BASE_URL="${DOWNLOADS_BASE_URL%/}"
APPCAST_PATH="${BUILD_DIR}/appcast.xml"
SPARKLE_WORK_DIR="${BUILD_DIR}/.sparkle"
BASELINE_ROOT="${BUILD_DIR}/baseline"
CURRENT_ZIP="${BUILD_DIR}/Voyager-${VERSION}.zip"
DOWNLOAD_PREFIX="${DOWNLOADS_BASE_URL}/releases/versions"

download_baseline_zip() {
  local version="$1"
  local target="${SPARKLE_WORK_DIR}/Voyager-${version}.zip"
  local url="${DOWNLOAD_PREFIX}/${version}/Voyager-${version}.zip"

  if [[ -f "${target}" ]]; then
    return 0
  fi

  curl -fsSL -o "${target}" "${url}"
}

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

# baseline_versions는 "이번 릴리즈 버전"을 제외한 기존 appcast 상단 N개 버전 목록을 의미한다.
# appcast에 아직 이번 버전이 없더라도, 해당 버전은 제외 대상으로만 사용된다.
baseline_versions=()
if [[ -n "${SPARKLE_BASELINE_COUNT}" && "${SPARKLE_BASELINE_COUNT}" != "0" && -f "${APPCAST_PATH}" ]]; then
  while IFS= read -r version; do
    [[ -n "${version}" ]] && baseline_versions+=("${version}")
  done < <(
    python3 "${SCRIPT_DIR}/resolve-sparkle-baseline-versions.py" \
      "${APPCAST_PATH}" "${VERSION}" "${SPARKLE_BASELINE_COUNT}"
  )
fi

# 선택된 버전 ZIP을 downloads 경로에서 내려받아 작업 디렉토리에 포함한다.
# 이렇게 모인 ZIP + 현재 ZIP을 기준으로 generate_appcast가 최종 appcast를 생성한다.
if (( ${#baseline_versions[@]} > 0 )); then
  for version in "${baseline_versions[@]}"; do
    [[ -z "${version}" ]] && continue
    download_baseline_zip "${version}"
  done
elif [[ -d "${BASELINE_ROOT}" ]]; then
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
  --maximum-deltas "${SPARKLE_MAXIMUM_DELTAS}" \
  --download-url-prefix "${DOWNLOAD_PREFIX}" \
  "${SPARKLE_WORK_DIR}"

python3 "${SCRIPT_DIR}/rewrite-sparkle-appcast-urls.py" \
  "${SPARKLE_WORK_DIR}/appcast.xml" "${DOWNLOAD_PREFIX}"

if [[ -f "${SPARKLE_WORK_DIR}/appcast.xml" && "${APPCAST_PATH}" != "${SPARKLE_WORK_DIR}/appcast.xml" ]]; then
  mkdir -p "$(dirname "${APPCAST_PATH}")"
  mv "${SPARKLE_WORK_DIR}/appcast.xml" "${APPCAST_PATH}"
fi

rm -rf "${SPARKLE_WORK_DIR}"
trap - EXIT
