#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
DMG_PATH="${2:-}"
if [[ -z "${APP_PATH}" || -z "${DMG_PATH}" ]]; then
  echo "Usage: $0 /path/to/Voyager.app /path/to/Voyager.dmg" >&2
  exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found: ${APP_PATH}" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d -t voyager-dmg-stage)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

mkdir -p "$(dirname "${DMG_PATH}")"
rm -f "${DMG_PATH}"

CONTENTS_DIR="${STAGE_DIR}/contents"
mkdir -p "${CONTENTS_DIR}"

cp -R "${APP_PATH}" "${CONTENTS_DIR}/Voyager.app"

CREATE_DMG_BIN=""
if command -v create-dmg >/dev/null 2>&1; then
  CREATE_DMG_BIN="create-dmg"
else
  CREATE_DMG_VERSION="${CREATE_DMG_VERSION:-v1.2.3}"
  CREATE_DMG_DOWNLOAD="${CREATE_DMG_DOWNLOAD:-1}"
  if [[ "${CREATE_DMG_DOWNLOAD}" == "1" ]] && command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    CREATE_DMG_ROOT="${STAGE_DIR}/create-dmg"
    CREATE_DMG_ARCHIVE="${CREATE_DMG_ROOT}/create-dmg.tar.gz"
    CREATE_DMG_TAG="${CREATE_DMG_VERSION}"
    if [[ "${CREATE_DMG_TAG}" != v* ]]; then
      CREATE_DMG_TAG="v${CREATE_DMG_TAG}"
    fi
    CREATE_DMG_URL="https://github.com/create-dmg/create-dmg/archive/refs/tags/${CREATE_DMG_TAG}.tar.gz"
    CREATE_DMG_DIR="${CREATE_DMG_ROOT}/create-dmg-${CREATE_DMG_TAG#v}"
    mkdir -p "${CREATE_DMG_ROOT}"
    if curl -fsSL "${CREATE_DMG_URL}" -o "${CREATE_DMG_ARCHIVE}"; then
      tar -xzf "${CREATE_DMG_ARCHIVE}" -C "${CREATE_DMG_ROOT}"
      if [[ -f "${CREATE_DMG_DIR}/create-dmg" ]]; then
        chmod +x "${CREATE_DMG_DIR}/create-dmg"
        CREATE_DMG_BIN="${CREATE_DMG_DIR}/create-dmg"
      fi
    fi
  fi
fi

if [[ -n "${CREATE_DMG_BIN}" ]]; then
  DMG_PRETTIFY="${DMG_PRETTIFY:-0}"

  CREATE_DMG_ARGS=(
    --volname "Voyager"
    --format UDZO
    --app-drop-link 470 190
    "${DMG_PATH}"
    "${CONTENTS_DIR}"
  )

  if [[ "${DMG_PRETTIFY}" == "1" ]]; then
    CREATE_DMG_ARGS=(
      --volname "Voyager"
      --format UDZO
      --window-size 640 400
      --icon-size 128
      --icon "Voyager.app" 170 190
      --hide-extension "Voyager.app"
      --app-drop-link 470 190
      "${DMG_PATH}"
      "${CONTENTS_DIR}"
    )
  else
    CREATE_DMG_ARGS=(--skip-jenkins "${CREATE_DMG_ARGS[@]}")
  fi

  "${CREATE_DMG_BIN}" "${CREATE_DMG_ARGS[@]}"
else
  ln -s /Applications "${CONTENTS_DIR}/Applications"
  hdiutil create \
    -volname "Voyager" \
    -srcfolder "${CONTENTS_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "DMG not created: ${DMG_PATH}" >&2
  exit 1
fi

echo "Created DMG: ${DMG_PATH}"
