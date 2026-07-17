#!/usr/bin/env bash
set -euo pipefail

OUT_PATH="${1:-}"
if [[ -z "${OUT_PATH}" ]]; then
  echo "Usage: $0 /path/to/release-identity.env" >&2
  exit 1
fi

: "${VOYAGER_RELEASED_AT:?Missing env: VOYAGER_RELEASED_AT}"

python3 - "${VOYAGER_RELEASED_AT}" <<'PY' > "${OUT_PATH}"
import datetime as dt
import re
import sys

released_at = sys.argv[1]
if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", released_at):
    raise SystemExit("VOYAGER_RELEASED_AT must be UTC RFC3339 with whole seconds")

try:
    parsed = dt.datetime.strptime(released_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
except ValueError as error:
    raise SystemExit(f"Invalid VOYAGER_RELEASED_AT: {error}") from error

if parsed > dt.datetime.now(dt.timezone.utc):
    raise SystemExit("VOYAGER_RELEASED_AT must not be in the future")

print(f"VOYAGER_RELEASED_AT={released_at}")
print(f"RELEASE_MANIFEST_RELEASED_AT={released_at}")
PY
