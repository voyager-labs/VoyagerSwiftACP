#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# just 설치 확인
if ! command -v just &>/dev/null; then
  echo ":: just 없음, brew로 설치 중..."
  brew install just
fi

# justfile 실행
just setup
