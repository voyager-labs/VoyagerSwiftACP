#!/usr/bin/env bash
set -euo pipefail

R2_BUCKET="${R2_BUCKET:-}"
VERSION_PREFIX="${VERSION_PREFIX:-}"
KEEP_COUNT="${KEEP_COUNT:-3}"

if [[ -z "${R2_BUCKET}" || -z "${VERSION_PREFIX}" ]]; then
  echo "Missing R2_BUCKET or VERSION_PREFIX." >&2
  exit 1
fi

list_json="$(
  wrangler r2 object list "${R2_BUCKET}" --prefix "${VERSION_PREFIX}/" --output json 2>/dev/null \
    || wrangler r2 object list "${R2_BUCKET}" --prefix "${VERSION_PREFIX}/" --json 2>/dev/null \
    || { echo "Warning: Failed to list R2 objects" >&2; exit 0; }
)"

if [[ -z "${list_json}" ]]; then
  echo "No versioned objects found; skipping prune."
  exit 0
fi

keys_to_delete="$(
  printf "%s" "${list_json}" | python3 - <<'PY'
import json
import os
import re
import sys

data = json.load(sys.stdin)
version_prefix = os.environ["VERSION_PREFIX"] + "/"
keep_count = int(os.environ.get("KEEP_COUNT", "3"))
versions = set()
keys = []

for item in data:
    key = item.get("key") or item.get("name") or ""
    if not key.startswith(version_prefix):
        continue
    rest = key[len(version_prefix):]
    version = rest.split("/", 1)[0]
    if version:
        versions.add(version)
        keys.append((version, key))

SEMVER_RE = re.compile(r"^(\\d+)\\.(\\d+)\\.(\\d+)(?:-([0-9A-Za-z.-]+))?$")

def semver_key(value: str):
    match = SEMVER_RE.match(value)
    if not match:
        return (-1, -1, -1, -1, [], value)

    major = int(match.group(1))
    minor = int(match.group(2))
    patch = int(match.group(3))

    prerelease = match.group(4)
    if prerelease is None:
        return (major, minor, patch, 1, [], value)

    identifiers = []
    for ident in prerelease.split("."):
        if ident.isdigit():
            identifiers.append((0, int(ident)))
        else:
            identifiers.append((1, ident))
    return (major, minor, patch, 0, identifiers, value)

versions_sorted = sorted(versions, key=semver_key)
remove_versions = set(versions_sorted[:-keep_count]) if len(versions_sorted) > keep_count else set()

for version, key in keys:
    if version in remove_versions:
        print(key)
PY
)"

if [[ -z "${keys_to_delete}" ]]; then
  echo "No old versions to prune."
  exit 0
fi

while IFS= read -r key; do
  [[ -z "${key}" ]] && continue
  wrangler r2 object delete "${R2_BUCKET}/${key}"
done <<< "${keys_to_delete}"
