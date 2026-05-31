#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# mise 설치 (공식 인스톨러)
command -v mise &>/dev/null || curl https://mise.run | sh

# mise.toml 신뢰 (새 클론 시 필요)
mise trust -q 2>/dev/null || true

# mise tasks로 setup 실행 (mise install, xcodes, lefthook, submodules)
echo "📦 mise run setup 실행 중..."
mise run setup

echo "✅ setup 완료"
