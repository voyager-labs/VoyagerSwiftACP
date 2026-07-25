#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH="${1:-}"
APP_PATH="${2:-}"
ZIP_PATH="${3:-}"
DMG_PATH="${4:-}"

if [[ -z "${ARCHIVE_PATH}" || -z "${APP_PATH}" || -z "${ZIP_PATH}" || -z "${DMG_PATH}" ]]; then
  echo "Usage: $0 /path/to/Voyager.xcarchive /path/to/Voyager.app /path/to/Voyager.zip /path/to/Voyager.dmg" >&2
  exit 1
fi

HELPER_PATH="${APP_PATH}/Contents/Helpers/VoyagerHelper.app"
XPC_PATH="${APP_PATH}/Contents/XPCServices/FilterSearchXPC.xpc"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/Voyager"
HELPER_EXECUTABLE="${HELPER_PATH}/Contents/MacOS/Voyager Helper"
XPC_EXECUTABLE="${XPC_PATH}/Contents/MacOS/FilterSearchXPC"
APP_DSYM="${ARCHIVE_PATH}/dSYMs/Voyager.app.dSYM/Contents/Resources/DWARF/Voyager"
HELPER_DSYM="${ARCHIVE_PATH}/dSYMs/VoyagerHelper.app.dSYM/Contents/Resources/DWARF/Voyager Helper"
XPC_DSYM="${ARCHIVE_PATH}/dSYMs/FilterSearchXPC.xpc.dSYM/Contents/Resources/DWARF/FilterSearchXPC"

for required_path in \
  "${APP_PATH}" \
  "${HELPER_PATH}" \
  "${XPC_PATH}" \
  "${APP_EXECUTABLE}" \
  "${HELPER_EXECUTABLE}" \
  "${XPC_EXECUTABLE}" \
  "${APP_DSYM}" \
  "${HELPER_DSYM}" \
  "${XPC_DSYM}" \
  "${ZIP_PATH}" \
  "${DMG_PATH}"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "Missing release artifact: ${required_path}" >&2
    exit 1
  fi
done

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  xcrun stapler validate "${DMG_PATH}"
  spctl --assess --type open --context context:primary-signature --verbose=4 "${DMG_PATH}"
fi

verify_uuid_match() {
  local label="$1"
  local executable="$2"
  local dsym="$3"
  local executable_uuids
  local dsym_uuids
  executable_uuids="$(dwarfdump --uuid "${executable}" | cut -d ' ' -f 2 | sort)"
  dsym_uuids="$(dwarfdump --uuid "${dsym}" | cut -d ' ' -f 2 | sort)"
  if [[ -z "${executable_uuids}" || "${executable_uuids}" != "${dsym_uuids}" ]]; then
    echo "${label} executable/dSYM UUID mismatch" >&2
    echo "executable: ${executable_uuids:-missing}" >&2
    echo "dSYM: ${dsym_uuids:-missing}" >&2
    exit 1
  fi
  echo "${label} UUID: ${executable_uuids}"
}

verify_no_development_links() {
  local label="$1"
  local executable="$2"
  local linked_libraries
  linked_libraries="$(otool -L "${executable}")"
  case "${linked_libraries}" in
    *Inject* | *HotSwiftUI* | *Injection*)
      echo "${label} contains a development-only linked library" >&2
      echo "${linked_libraries}" >&2
      exit 1
      ;;
  esac
  echo "${label} linked libraries verified"
}

verify_uuid_match "Voyager" "${APP_EXECUTABLE}" "${APP_DSYM}"
verify_uuid_match "VoyagerHelper" "${HELPER_EXECUTABLE}" "${HELPER_DSYM}"
verify_uuid_match "FilterSearchXPC" "${XPC_EXECUTABLE}" "${XPC_DSYM}"
verify_no_development_links "Voyager" "${APP_EXECUTABLE}"
verify_no_development_links "VoyagerHelper" "${HELPER_EXECUTABLE}"
verify_no_development_links "FilterSearchXPC" "${XPC_EXECUTABLE}"

python3 - "${APP_PATH}" "${HELPER_PATH}" "${XPC_PATH}" "${ZIP_PATH}" "${DMG_PATH}" <<'PY'
from pathlib import Path
import sys


def artifact_size(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(
        candidate.stat().st_size
        for candidate in path.rglob("*")
        if candidate.is_file() and not candidate.is_symlink()
    )


for artifact_name in sys.argv[1:]:
    artifact = Path(artifact_name)
    print(f"artifact-size\t{artifact.name}\t{artifact_size(artifact)}")
PY
