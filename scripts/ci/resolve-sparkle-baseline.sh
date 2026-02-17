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
  versions=()
  while IFS= read -r version; do
    [[ -n "${version}" ]] && versions+=("${version}")
  done < <(
    python3 - "${APPCAST_PATH}" <<'PY'
import re
import sys

appcast_path = sys.argv[1]
with open(appcast_path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(r"Voyager-([0-9A-Za-z][0-9A-Za-z.\-]*)\.zip")
seen = set()
versions = []
for match in pattern.finditer(content):
    version = match.group(1)
    if version in seen:
        continue
    seen.add(version)
    versions.append(version)

print("\n".join(versions))
PY
  )

  if (( ${#versions[@]} > 0 )); then
    prev_version=""
    for candidate in "${versions[@]}"; do
      if [[ "${candidate}" == "${VERSION}" ]]; then
        continue
      fi
      prev_version="${candidate}"
      break
    done

    if [[ -z "${prev_version}" ]]; then
      prev_version="${versions[0]}"
    fi

    if [[ -n "${prev_version}" ]]; then
      has_baseline="true"
      prev_key="releases/versions/${prev_version}/Voyager-${prev_version}.zip"
      prev_name="Voyager-${prev_version}.zip"
    fi
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "has_baseline=${has_baseline}"
    echo "prev_key=${prev_key}"
    echo "prev_name=${prev_name}"
  } >> "${GITHUB_OUTPUT}"
fi
