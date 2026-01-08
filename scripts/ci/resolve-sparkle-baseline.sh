#!/usr/bin/env bash
set -euo pipefail

APPCAST_PATH="${1:-}"

if [[ -z "${APPCAST_PATH}" ]]; then
  echo "Usage: $0 /path/to/appcast.xml" >&2
  exit 1
fi

has_baseline="false"
prev_key=""
prev_name=""

if [[ -f "${APPCAST_PATH}" ]]; then
  has_baseline="true"
  prev_key="$(python3 - "${APPCAST_PATH}" <<'PY' || true
import sys
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

path = sys.argv[1]
try:
    tree = ET.parse(path)
except ET.ParseError:
    sys.exit(0)
root = tree.getroot()
enclosure = root.find(".//item/enclosure")
if enclosure is None:
    sys.exit(0)
url = enclosure.get("url") or ""
if not url:
    sys.exit(0)
parsed = urlparse(url)
key = parsed.path.lstrip("/")
if key:
    print(key)
PY
)"
  if [[ -n "${prev_key}" ]]; then
    prev_name="$(basename "${prev_key}")"
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "has_baseline=${has_baseline}"
    echo "prev_key=${prev_key}"
    echo "prev_name=${prev_name}"
  } >> "${GITHUB_OUTPUT}"
fi
