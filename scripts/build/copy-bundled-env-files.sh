#!/usr/bin/env bash
# Release/bundled에서 번들 리소스에 환경 파일을 복사합니다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

if [[ "${APP_ENV:-}" != "prod" ]]; then
  echo "[Voyager] Skip env copy for APP_ENV=${APP_ENV:-unset}" >&2
  exit 0
fi

DEST_DIR="${1:-}"
if [[ -z "${DEST_DIR}" ]]; then
  if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
    echo "[Voyager] TARGET_BUILD_DIR 또는 UNLOCALIZED_RESOURCES_FOLDER_PATH가 없습니다" >&2
    exit 1
  fi
  DEST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
fi

if [[ ! -d "${DEST_DIR}" ]]; then
  echo "[Voyager] Resource dir missing: ${DEST_DIR}" >&2
  exit 1
fi

ENV_PROD_SRC="${REPO_ROOT}/.env.prod"

if [[ ! -f "${ENV_PROD_SRC}" ]]; then
  echo "[Voyager] .env.prod not found: ${ENV_PROD_SRC}" >&2
  exit 1
fi
if [[ -z "${PUBLIC_POSTHOG_PROJECT_TOKEN//[[:space:]]/}" ]]; then
  echo "[Voyager] Missing env: PUBLIC_POSTHOG_PROJECT_TOKEN" >&2
  exit 1
fi
if [[ -z "${PUBLIC_POSTHOG_HOST//[[:space:]]/}" ]]; then
  echo "[Voyager] Missing env: PUBLIC_POSTHOG_HOST" >&2
  exit 1
fi

output_path="${DEST_DIR}/.env.prod"
temp_path="$(mktemp "${DEST_DIR}/.env.prod.tmp.XXXXXX")"
trap 'rm -f "${temp_path}"' EXIT
PUBLIC_POSTHOG_PROJECT_TOKEN="${PUBLIC_POSTHOG_PROJECT_TOKEN}" \
  PUBLIC_POSTHOG_HOST="${PUBLIC_POSTHOG_HOST}" \
  python3 - "${ENV_PROD_SRC}" "${temp_path}" <<'PY'
import os
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
replacements = {
    "PUBLIC_POSTHOG_HOST": os.environ.get("PUBLIC_POSTHOG_HOST", ""),
    "PUBLIC_POSTHOG_PROJECT_TOKEN": os.environ.get(
        "PUBLIC_POSTHOG_PROJECT_TOKEN", ""
    ),
}
for key, value in replacements.items():
    if "\n" in value or "\r" in value:
        print(f"Invalid env value: {key}", file=sys.stderr)
        raise SystemExit(1)
source = source_path.read_text(encoding="utf-8")
lines = source.splitlines(keepends=True)
counts = {key: 0 for key in replacements}
output: list[str] = []
for line in lines:
    matched_key = next(
        (key for key in replacements if re.match(rf"^{re.escape(key)}=", line)),
        None,
    )
    if matched_key is None:
        output.append(line)
        continue
    counts[matched_key] += 1
    if counts[matched_key] > 1:
        print(f"Duplicate env key: {matched_key}", file=sys.stderr)
        raise SystemExit(1)
    output.append(f"{matched_key}={replacements[matched_key]}\n")

for key, count in counts.items():
    if count != 1:
        print(f"Missing env key: {key}", file=sys.stderr)
        raise SystemExit(1)
output_path.write_text("".join(output), encoding="utf-8")
PY
mv -f "${temp_path}" "${output_path}"
trap - EXIT
echo "[Voyager] .env.prod 복사 완료: ${DEST_DIR}/.env.prod" >&2
