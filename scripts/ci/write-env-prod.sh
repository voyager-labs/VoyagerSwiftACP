#!/usr/bin/env bash
set -euo pipefail

OUT_PATH="${1:-}"
if [[ -z "${OUT_PATH}" ]]; then
  echo "Usage: $0 /path/to/.env.prod" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_PATH}")"

cat >"${OUT_PATH}" <<'EOF'
APP_ENV=prod
BACKEND_DIR=backend-venv
VOYAGER_HOST=127.0.0.1
VOYAGER_PORT=8000
BACKEND_URL=http://127.0.0.1:8000
VOYAGER_PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin
VOYAGER_LOG_FILE=~/Library/Logs/Voyager/voyager.log
EOF

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  printf "OPENAI_API_KEY=%s\n" "${OPENAI_API_KEY}" >>"${OUT_PATH}"
fi
if [[ -n "${OPENAI_ORG_ID:-}" ]]; then
  printf "OPENAI_ORG_ID=%s\n" "${OPENAI_ORG_ID}" >>"${OUT_PATH}"
fi
if [[ -n "${OPENAI_PROJECT:-}" ]]; then
  printf "OPENAI_PROJECT=%s\n" "${OPENAI_PROJECT}" >>"${OUT_PATH}"
fi

echo "Wrote CI .env.prod: ${OUT_PATH}"

