#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

export PATH="$HOME/.local/bin:$PATH"

command -v mise &>/dev/null || curl https://mise.run | sh

mise trust -q 2>/dev/null || true

echo "📦 mise run setup 실행 중..."
mise run setup

echo "✅ setup 완료"
