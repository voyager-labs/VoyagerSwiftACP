#!/usr/bin/env bash
set -euo pipefail

APPCAST_PATH="${1:-}"
VERSION="${2:-}"

if [[ -z "${APPCAST_PATH}" || -z "${VERSION}" ]]; then
  echo "Usage: $0 /path/to/appcast.xml <version>" >&2
  exit 1
fi

has_baseline="false"
prev_key=""
prev_name=""

if [[ -f "${APPCAST_PATH}" ]]; then
  has_baseline="true"
  prev_key="releases/versions/${VERSION}/Voyager-${VERSION}.zip"
  prev_name="Voyager-${VERSION}.zip"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "has_baseline=${has_baseline}"
    echo "prev_key=${prev_key}"
    echo "prev_name=${prev_name}"
  } >> "${GITHUB_OUTPUT}"
fi
