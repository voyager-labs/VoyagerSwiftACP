#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

if ! command -v mise >/dev/null 2>&1; then
  curl https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

mise trust -y "$PWD/mise.toml"

echo "📦 mise run setup 실행 중..."
mise run setup

echo "✅ setup 완료"
