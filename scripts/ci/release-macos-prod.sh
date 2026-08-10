#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build/ci}"
PROJECT_PATH="${PROJECT_PATH:-apps/macos/Voyager/Voyager.xcodeproj}"
SCHEME="${SCHEME:-Voyager-Prod}"
CONFIGURATION="${CONFIGURATION:-Prod-Release}"
CURRENT_PROJECT_VERSION_OVERRIDE="${CURRENT_PROJECT_VERSION_OVERRIDE:-}"
VOYAGER_RELEASED_AT="${VOYAGER_RELEASED_AT:-}"

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
  --dry-run       - hardening gate를 검증하고 종료합니다 (archive/notarize 생략).
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
    validate_gated_version "${VERSION}"
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
  validate_gated_version "${VERSION}"
  export VERSION
}

validate_gated_version() {
  if ! python3 - "$1" <<'PY'
import re
import sys

match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-[A-Za-z0-9.]+)?", sys.argv[1])
if not match or tuple(map(int, match.groups()[:3])) < (0, 8, 2):
    raise SystemExit("The first gated Sparkle release is v0.8.2; earlier releases are not supported.")
PY
  then
    exit 1
  fi
}

hardening_gate() {
  # Hardening gate: only Prod-Release + Voyager-Prod can deploy
  if [[ "${CONFIGURATION}" != "Prod-Release" ]]; then
    echo "error: only Prod-Release can be released (got: ${CONFIGURATION})" >&2
    exit 1
  fi
  if [[ "${SCHEME}" != "Voyager-Prod" ]]; then
    echo "error: only Voyager-Prod scheme can be released (got: ${SCHEME})" >&2
    exit 1
  fi
  log "Hardening gate passed (CONFIGURATION=Prod-Release, SCHEME=Voyager-Prod)"
}

verify_archive_artifacts() {
  local app_path="${BUILD_DIR}/export/Voyager.app"
  local helper_path="${app_path}/Contents/Helpers/VoyagerHelper.app"
  local xpc_path="${app_path}/Contents/XPCServices/FilterSearchXPC.xpc"
  local errors=0

  log "Verifying release artifact invariants..."

  # --- Info.plist checks ---

  # 1. Voyager.app: APP_ENV == prod
  local app_env
  app_env="$(plutil -p "${app_path}/Contents/Info.plist" | grep '"APP_ENV"' | sed 's/.*"APP_ENV" => "\(.*\)"/\1/')"
  if [[ "${app_env}" != "prod" ]]; then
    echo "error: Voyager.app APP_ENV is '${app_env}', expected 'prod'" >&2
    errors=$((errors + 1))
  else
    log "  ✓ Voyager.app APP_ENV = prod"
  fi

  # 2. Voyager.app: CFBundleIdentifier == fm.voyager.Voyager
  local bundle_id
  bundle_id="$(plutil -p "${app_path}/Contents/Info.plist" | grep '"CFBundleIdentifier"' | sed 's/.*"CFBundleIdentifier" => "\(.*\)"/\1/')"
  if [[ "${bundle_id}" != "fm.voyager.Voyager" ]]; then
    echo "error: Voyager.app CFBundleIdentifier is '${bundle_id}', expected 'fm.voyager.Voyager'" >&2
    errors=$((errors + 1))
  else
    log "  ✓ Voyager.app CFBundleIdentifier = fm.voyager.Voyager"
  fi

  # 3. Voyager.app: SUFeedURL == canonical prod appcast
  local feed_url
  feed_url="$(plutil -p "${app_path}/Contents/Info.plist" | grep '"SUFeedURL"' | sed 's/.*"SUFeedURL" => "\(.*\)"/\1/')"
  if [[ "${feed_url}" != "https://downloads.voyager.fm/releases/appcast.xml" ]]; then
    echo "error: Voyager.app SUFeedURL is '${feed_url}', expected 'https://downloads.voyager.fm/releases/appcast.xml'" >&2
    errors=$((errors + 1))
  else
    log "  ✓ Voyager.app SUFeedURL = https://downloads.voyager.fm/releases/appcast.xml"
  fi

  # 4. VoyagerHelper.app: APP_ENV == prod
  if [[ -d "${helper_path}" ]]; then
    local helper_env
    helper_env="$(plutil -p "${helper_path}/Contents/Info.plist" | grep '"APP_ENV"' | sed 's/.*"APP_ENV" => "\(.*\)"/\1/')"
    if [[ "${helper_env}" != "prod" ]]; then
      echo "error: VoyagerHelper.app APP_ENV is '${helper_env}', expected 'prod'" >&2
      errors=$((errors + 1))
    else
      log "  ✓ VoyagerHelper.app APP_ENV = prod"
    fi
  else
    echo "error: VoyagerHelper.app not found at ${helper_path}" >&2
    errors=$((errors + 1))
  fi

  # 5. FilterSearchXPC.xpc: Mach service name is prod variant
  if [[ -d "${xpc_path}" ]]; then
    local mach_service
    mach_service="$(/usr/libexec/PlistBuddy -c 'Print :MachServices' "${xpc_path}/Contents/Info.plist" | sed -n 's/^[[:space:]]*\([^ =][^=]*\) = true$/\1/p')"
    if [[ "${mach_service}" != "fm.voyager.Voyager.FilterSearchXPC" ]]; then
      echo "error: FilterSearchXPC Mach service name is '${mach_service}', expected 'fm.voyager.Voyager.FilterSearchXPC'" >&2
      errors=$((errors + 1))
    else
      log "  ✓ FilterSearchXPC Mach service = fm.voyager.Voyager.FilterSearchXPC"
    fi
  else
    echo "error: FilterSearchXPC.xpc not found at ${xpc_path}" >&2
    errors=$((errors + 1))
  fi

  # 6. CODE_SIGN_IDENTITY of all 3 binaries is Developer ID Application
  # 7. Hardened runtime (runtime flag) is enabled
  for binary_path in "${app_path}" "${helper_path}" "${xpc_path}"; do
    if [[ ! -d "${binary_path}" ]]; then
      continue
    fi
    local codesign_out
    codesign_out="$(codesign -dv --verbose=4 "${binary_path}" 2>&1 || true)"

    # Check Developer ID Application
    if echo "${codesign_out}" | grep -q "Developer ID Application"; then
      log "  ✓ $(basename "${binary_path}"): signed with Developer ID Application"
    else
      echo "error: $(basename "${binary_path}") is not signed with Developer ID Application" >&2
      echo "  codesign output: ${codesign_out}" >&2
      errors=$((errors + 1))
    fi

    # Check hardened runtime
    if echo "${codesign_out}" | grep -q "flags.*runtime"; then
      log "  ✓ $(basename "${binary_path}"): hardened runtime enabled"
    else
      echo "error: $(basename "${binary_path}") does not have hardened runtime enabled" >&2
      errors=$((errors + 1))
    fi
  done

  if [[ "${errors}" -gt 0 ]]; then
    echo "error: ${errors} artifact verification check(s) failed" >&2
    exit 1
  fi

  log "All release artifact invariants verified."
}

prepare_release_identity() {
  : "${VOYAGER_RELEASED_AT:?Missing env: VOYAGER_RELEASED_AT}"
  local identity_env_path="${BUILD_DIR}/release-identity.env"

  VOYAGER_RELEASED_AT="${VOYAGER_RELEASED_AT}" \
    bash "${SCRIPT_DIR}/prepare-release-identity.sh" "${identity_env_path}"
  # shellcheck source=/dev/null
  source "${identity_env_path}"
  export VOYAGER_RELEASED_AT RELEASE_MANIFEST_RELEASED_AT
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
  hardening_gate
  prepare_release_identity
  : "${DOWNLOADS_BASE_URL:?Missing env: DOWNLOADS_BASE_URL}"
  : "${SPARKLE_PRIVATE_KEY:?Missing env: SPARKLE_PRIVATE_KEY}"

  export BUILD_DIR PROJECT_PATH SCHEME CONFIGURATION CURRENT_PROJECT_VERSION_OVERRIDE VOYAGER_RELEASED_AT
  export DOWNLOADS_BASE_URL SPARKLE_PRIVATE_KEY SPARKLE_BASELINE_COUNT VERSION

  log "Building archive..."
  "${SCRIPT_DIR}/build-archive.sh"

  log "Exporting app..."
  "${SCRIPT_DIR}/export-macos-app.sh" "${BUILD_DIR}/Voyager.xcarchive" "${BUILD_DIR}/export"

  verify_archive_artifacts

  log "Creating DMG..."
  uv run "${SCRIPT_DIR}/create-dmg.py" "${BUILD_DIR}/export/Voyager.app" "${BUILD_DIR}/Voyager.dmg"

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

  log "Verifying optimized release artifacts..."
  "${SCRIPT_DIR}/verify-release-artifacts.sh" \
    "${BUILD_DIR}/Voyager.xcarchive" \
    "${BUILD_DIR}/export/Voyager.app" \
    "${BUILD_DIR}/Voyager-${VERSION}.zip" \
    "${BUILD_DIR}/Voyager.dmg"

  log "Generating Sparkle appcast..."
  "${SCRIPT_DIR}/generate-sparkle-appcast.sh"

  log "Generating signed release manifest..."
  python3 "${SCRIPT_DIR}/generate-release-manifest.py" \
    "${BUILD_DIR}/Voyager-${VERSION}.zip" \
    "${BUILD_DIR}/appcast.xml" \
    "${DOWNLOADS_BASE_URL%/}/releases/versions/${VERSION}/Voyager-${VERSION}.zip" \
    "${VERSION}" \
    "${RELEASE_MANIFEST_RELEASED_AT}" \
    "${BUILD_DIR}/release-manifest-v1.json"

  log "Verifying signed release manifest..."
  xcrun swiftc \
    "${REPO_ROOT}/apps/macos/Packages/06_Shared/VoyagerShared/Sources/VoyagerShared/Model/AppVersionInfo.swift" \
    "${REPO_ROOT}/apps/macos/Packages/06_Shared/VoyagerShared/Sources/VoyagerShared/Model/ReleaseManifest.swift" \
    "${SCRIPT_DIR}/release-manifest-verifier/main.swift" \
    -o "${BUILD_DIR}/verify-release-manifest"
  SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY}" "${BUILD_DIR}/verify-release-manifest" \
    "${BUILD_DIR}/release-manifest-v1.json" \
    "${BUILD_DIR}/Voyager-${VERSION}.zip" \
    "${BUILD_DIR}/appcast.xml" \
    "${DOWNLOADS_BASE_URL%/}/releases/versions/${VERSION}/Voyager-${VERSION}.zip" \
    "${RELEASE_MANIFEST_RELEASED_AT}"
}

generate_latest() {
  resolve_version
  prepare_release_identity
  local dmg_path="${BUILD_DIR}/Voyager.dmg"
  local out_path="${BUILD_DIR}/latest.json"
  local manifest_path="${BUILD_DIR}/release-manifest-v1.json"
  local versioned_url="${VERSION_PREFIX}/${VERSION}/Voyager.dmg"
  local latest_url="${RELEASES_PREFIX}/Voyager.dmg"

  [[ -f "${manifest_path}" ]] || { echo "Missing file: ${manifest_path}" >&2; exit 1; }
  VOYAGER_RELEASED_AT="${RELEASE_MANIFEST_RELEASED_AT}" "${SCRIPT_DIR}/generate-latest-json.sh" \
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
  local manifest_path="${BUILD_DIR}/release-manifest-v1.json"

  [[ -f "${dmg_path}" ]] || { echo "Missing file: ${dmg_path}" >&2; exit 1; }
  [[ -f "${zip_path}" ]] || { echo "Missing file: ${zip_path}" >&2; exit 1; }
  [[ -f "${appcast_path}" ]] || { echo "Missing file: ${appcast_path}" >&2; exit 1; }
  [[ -f "${manifest_path}" ]] || { echo "Missing file: ${manifest_path}" >&2; exit 1; }

  generate_latest
  [[ -f "${latest_path}" ]] || { echo "Missing file: ${latest_path}" >&2; exit 1; }

  log "Uploading files to R2..."
  wrangler r2 object put "${R2_BUCKET}/${VERSION_PREFIX}/${VERSION}/Voyager.dmg" --remote --file "${dmg_path}"
  wrangler r2 object put "${R2_BUCKET}/${RELEASES_PREFIX}/Voyager.dmg" --remote --file "${dmg_path}"
  wrangler r2 object put "${R2_BUCKET}/${RELEASES_PREFIX}/latest.json" --remote --file "${latest_path}"
  wrangler r2 object put "${R2_BUCKET}/${VERSION_PREFIX}/${VERSION}/release-manifest-v1.json" --remote --file "${manifest_path}"
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
    --dry-run)
      hardening_gate
      log "Dry-run: hardening gate passed, no archive produced."
      ;;
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
