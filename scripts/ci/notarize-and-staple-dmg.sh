#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:-}"
if [[ -z "${DMG_PATH}" ]]; then
  echo "Usage: $0 /path/to/Voyager.dmg" >&2
  exit 1
fi
if [[ ! -f "${DMG_PATH}" ]]; then
  echo "DMG not found: ${DMG_PATH}" >&2
  exit 1
fi

if [[ -z "${ASC_ISSUER_ID:-}" ]]; then
  echo "Missing env: ASC_ISSUER_ID" >&2
  exit 1
fi
if [[ -z "${ASC_KEY_ID:-}" ]]; then
  echo "Missing env: ASC_KEY_ID" >&2
  exit 1
fi
if [[ -z "${ASC_PRIVATE_KEY_P8:-}" ]]; then
  echo "Missing env: ASC_PRIVATE_KEY_P8" >&2
  exit 1
fi

P8_PATH="$(mktemp -t asc_key).p8"
trap 'rm -f "${P8_PATH}"' EXIT
printf "%s" "${ASC_PRIVATE_KEY_P8}" >"${P8_PATH}"

echo "Signing DMG..."
codesign --force --timestamp --sign "Developer ID Application: Voyager for Momentum Inc. (UNR9C79D99)" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

echo "Submitting for notarization..."
xcrun notarytool submit "${DMG_PATH}" \
  --issuer "${ASC_ISSUER_ID}" \
  --key-id "${ASC_KEY_ID}" \
  --key "${P8_PATH}" \
  --wait

echo "Stapling ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "Notarized + stapled: ${DMG_PATH}"
