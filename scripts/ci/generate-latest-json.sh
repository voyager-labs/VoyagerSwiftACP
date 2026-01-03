#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:-}"
VERSION="${2:-}"
VERSIONED_URL="${3:-}"
LATEST_URL="${4:-}"
OUT_PATH="${5:-}"

if [[ -z "${DMG_PATH}" || -z "${VERSION}" || -z "${VERSIONED_URL}" || -z "${LATEST_URL}" || -z "${OUT_PATH}" ]]; then
  echo "Usage: $0 /path/to/Voyager.dmg 1.2.3 <versioned-url> <latest-url> /path/to/latest.json" >&2
  exit 1
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "DMG not found: ${DMG_PATH}" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
SIZE_BYTES="$(stat -f%z "${DMG_PATH}")"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$(dirname "${OUT_PATH}")"

cat >"${OUT_PATH}" <<EOF
{
  "version": "${VERSION}",
  "publishedAt": "${PUBLISHED_AT}",
  "sha256": "${SHA256}",
  "sizeBytes": ${SIZE_BYTES},
  "url": "${LATEST_URL}",
  "versionedUrl": "${VERSIONED_URL}"
}
EOF

echo "Wrote latest.json: ${OUT_PATH}"

