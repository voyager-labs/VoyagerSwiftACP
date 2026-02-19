#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build/ci}"
PROJECT_PATH="${PROJECT_PATH:-apps/macos/Voyager/Voyager.xcodeproj}"
SCHEME="${SCHEME:-Voyager-Prod}"
CONFIGURATION="${CONFIGURATION:-Release}"
CURRENT_PROJECT_VERSION_OVERRIDE="${CURRENT_PROJECT_VERSION_OVERRIDE:-}"

RELEASES_PREFIX="${RELEASES_PREFIX:-releases}"
VERSION_PREFIX="${VERSION_PREFIX:-releases/versions}"
SPARKLE_APPCAST_KEY="${SPARKLE_APPCAST_KEY:-${RELEASES_PREFIX}/appcast.xml}"
SPARKLE_BASELINE_COUNT="${SPARKLE_BASELINE_COUNT:-2}"

log() {
  echo "[release-macos-prod] $*"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/ci/release-macos-prod.sh <command>

Commands:
  fetch-baseline  - appcast/baseline zip을 build/ci로 가져옵니다.
  build-notarize  - archive/export/dmg/notarize/zip/appcast를 생성합니다.
  generate-latest - latest.json만 생성합니다.
  upload-r2       - latest.json 생성 후 R2에 업로드합니다.
  run-local       - fetch-baseline -> build-notarize -> upload-r2 순서로 실행합니다.

Required env (공통):
  VERSION 또는 TAG(예: v1.2.3)

Required env (build-notarize):
  DOWNLOADS_BASE_URL
  SPARKLE_PRIVATE_KEY
  ASC_ISSUER_ID, ASC_KEY_ID, ASC_PRIVATE_KEY_P8 (SKIP_NOTARIZE=1이 아닐 때)

Required env (upload-r2):
  R2_BUCKET
  CLOUDFLARE_API_TOKEN
  CLOUDFLARE_ACCOUNT_ID
EOF
}

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    export VERSION
    return
  fi

  local tag="${TAG:-${GITHUB_REF_NAME:-}}"
  if [[ -z "${tag}" ]]; then
    echo "Missing VERSION or TAG." >&2
    exit 1
  fi
  if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Expected semantic version tag like v1.2.3, got: ${tag}" >&2
    exit 1
  fi

  VERSION="${tag#v}"
  export VERSION
}

have_wrangler() {
  command -v wrangler >/dev/null 2>&1
}

have_r2_credentials() {
  [[ -n "${R2_BUCKET:-}" && -n "${CLOUDFLARE_API_TOKEN:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]]
}

require_r2_ready() {
  if ! have_wrangler; then
    echo "wrangler command not found." >&2
    exit 1
  fi
  : "${R2_BUCKET:?Missing env: R2_BUCKET}"
  : "${CLOUDFLARE_API_TOKEN:?Missing env: CLOUDFLARE_API_TOKEN}"
  : "${CLOUDFLARE_ACCOUNT_ID:?Missing env: CLOUDFLARE_ACCOUNT_ID}"
}

fetch_baseline() {
  resolve_version
  mkdir -p "${BUILD_DIR}" "${BUILD_DIR}/baseline"

  if have_wrangler && have_r2_credentials; then
    log "Downloading appcast from R2..."
    if ! wrangler r2 object get "${R2_BUCKET}/${SPARKLE_APPCAST_KEY}" --remote --file "${BUILD_DIR}/appcast.xml"; then
      log "Appcast download failed. Continue without baseline."
    fi
  else
    log "Skip appcast download (wrangler or R2 credentials missing)."
  fi

  local output_file
  output_file="$(mktemp)"
  GITHUB_OUTPUT="${output_file}" "${SCRIPT_DIR}/resolve-sparkle-baseline.sh" "${BUILD_DIR}/appcast.xml" "${VERSION}"

  local has_baseline="false"
  local prev_key=""
  local prev_name=""
  while IFS='=' read -r key value; do
    case "${key}" in
      has_baseline) has_baseline="${value}" ;;
      prev_key) prev_key="${value}" ;;
      prev_name) prev_name="${value}" ;;
    esac
  done < "${output_file}"
  rm -f "${output_file}"

  if [[ "${has_baseline}" != "true" || -z "${prev_key}" || -z "${prev_name}" ]]; then
    log "No baseline zip found."
    return
  fi

  if have_wrangler && have_r2_credentials; then
    log "Downloading baseline zip from R2..."
    if ! wrangler r2 object get "${R2_BUCKET}/${prev_key}" --remote --file "${BUILD_DIR}/baseline/${prev_name}"; then
      log "Baseline zip download failed. Continue."
    fi
  else
    log "Skip baseline zip download (wrangler or R2 credentials missing)."
  fi
}

build_notarize() {
  resolve_version
  : "${DOWNLOADS_BASE_URL:?Missing env: DOWNLOADS_BASE_URL}"
  : "${SPARKLE_PRIVATE_KEY:?Missing env: SPARKLE_PRIVATE_KEY}"

  export BUILD_DIR PROJECT_PATH SCHEME CONFIGURATION CURRENT_PROJECT_VERSION_OVERRIDE
  export DOWNLOADS_BASE_URL SPARKLE_PRIVATE_KEY SPARKLE_BASELINE_COUNT VERSION

  log "Building archive..."
  "${SCRIPT_DIR}/build-archive.sh"

  log "Exporting app..."
  "${SCRIPT_DIR}/export-macos-app.sh" "${BUILD_DIR}/Voyager.xcarchive" "${BUILD_DIR}/export"

  log "Creating DMG..."
  "${SCRIPT_DIR}/create-dmg.sh" "${BUILD_DIR}/export/Voyager.app" "${BUILD_DIR}/Voyager.dmg"

  if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    log "Skipping notarization (SKIP_NOTARIZE=1)."
  else
    : "${ASC_ISSUER_ID:?Missing env: ASC_ISSUER_ID}"
    : "${ASC_KEY_ID:?Missing env: ASC_KEY_ID}"
    : "${ASC_PRIVATE_KEY_P8:?Missing env: ASC_PRIVATE_KEY_P8}"

    log "Notarizing DMG..."
    "${SCRIPT_DIR}/notarize-and-staple-dmg.sh" "${BUILD_DIR}/Voyager.dmg"
  fi

  log "Creating Sparkle zip..."
  "${SCRIPT_DIR}/create-sparkle-zip.sh"

  log "Generating Sparkle appcast..."
  "${SCRIPT_DIR}/generate-sparkle-appcast.sh"
}

generate_latest() {
  resolve_version
  local dmg_path="${BUILD_DIR}/Voyager.dmg"
  local out_path="${BUILD_DIR}/latest.json"
  local versioned_url="${VERSION_PREFIX}/${VERSION}/Voyager.dmg"
  local latest_url="${RELEASES_PREFIX}/Voyager.dmg"

  "${SCRIPT_DIR}/generate-latest-json.sh" \
    "${dmg_path}" \
    "${VERSION}" \
    "${versioned_url}" \
    "${latest_url}" \
    "${out_path}"
}

upload_r2() {
  resolve_version
  require_r2_ready

  local dmg_path="${BUILD_DIR}/Voyager.dmg"
  local zip_path="${BUILD_DIR}/Voyager-${VERSION}.zip"
  local appcast_path="${BUILD_DIR}/appcast.xml"
  local latest_path="${BUILD_DIR}/latest.json"

  [[ -f "${dmg_path}" ]] || { echo "Missing file: ${dmg_path}" >&2; exit 1; }
  [[ -f "${zip_path}" ]] || { echo "Missing file: ${zip_path}" >&2; exit 1; }
  [[ -f "${appcast_path}" ]] || { echo "Missing file: ${appcast_path}" >&2; exit 1; }

  generate_latest
  [[ -f "${latest_path}" ]] || { echo "Missing file: ${latest_path}" >&2; exit 1; }

  log "Uploading files to R2..."
  wrangler r2 object put "${R2_BUCKET}/${VERSION_PREFIX}/${VERSION}/Voyager.dmg" --remote --file "${dmg_path}"
  wrangler r2 object put "${R2_BUCKET}/${RELEASES_PREFIX}/Voyager.dmg" --remote --file "${dmg_path}"
  wrangler r2 object put "${R2_BUCKET}/${RELEASES_PREFIX}/latest.json" --remote --file "${latest_path}"
  wrangler r2 object put "${R2_BUCKET}/${VERSION_PREFIX}/${VERSION}/Voyager-${VERSION}.zip" --remote --file "${zip_path}"
  wrangler r2 object put "${R2_BUCKET}/${SPARKLE_APPCAST_KEY}" --remote --file "${appcast_path}"
}

run_local() {
  fetch_baseline
  build_notarize
  upload_r2
}

main() {
  cd "${REPO_ROOT}"

  local cmd="${1:-}"
  case "${cmd}" in
    fetch-baseline)
      fetch_baseline
      ;;
    build-notarize)
      build_notarize
      ;;
    generate-latest)
      generate_latest
      ;;
    upload-r2)
      upload_r2
      ;;
    run-local)
      run_local
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
