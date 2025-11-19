#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f .xcode-version ]; then
  echo ".xcode-version file not found in repo root"
  exit 1
fi

VERSION="$(cat .xcode-version | tr -d '[:space:]')"

if [ -z "$VERSION" ]; then
  echo ".xcode-version is empty"
  exit 1
fi

echo "🔧 Using Xcode version: $VERSION"

# xcodes 설치 여부 확인
if ! command -v xcodes >/dev/null 2>&1; then
  echo "ℹ️  xcodes CLI not found. Installing via Homebrew..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew is not installed. Install Homebrew first."
    exit 1
  fi
  brew install xcodes
fi

echo "📦 Installing Xcode $VERSION if needed..."
xcodes install "$VERSION"

echo "✅ Selecting Xcode $VERSION"
xcodes select "$VERSION"

echo "✅ Xcode $VERSION is now the active version for this machine."
