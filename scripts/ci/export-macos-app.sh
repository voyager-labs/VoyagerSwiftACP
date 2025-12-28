#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH="${1:-}"
EXPORT_DIR="${2:-}"
if [[ -z "${ARCHIVE_PATH}" || -z "${EXPORT_DIR}" ]]; then
  echo "Usage: $0 /path/to/App.xcarchive /path/to/export-dir" >&2
  exit 1
fi

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  echo "Archive not found: ${ARCHIVE_PATH}" >&2
  exit 1
fi

mkdir -p "${EXPORT_DIR}"

EXPORT_OPTIONS_PLIST="$(mktemp -t exportOptions).plist"
cat >"${EXPORT_OPTIONS_PLIST}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

if [[ ! -d "${EXPORT_DIR}/Voyager.app" ]]; then
  echo "Expected app not found at: ${EXPORT_DIR}/Voyager.app" >&2
  echo "Export directory contents:" >&2
  ls -la "${EXPORT_DIR}" >&2 || true
  exit 1
fi

echo "Exported app: ${EXPORT_DIR}/Voyager.app"
