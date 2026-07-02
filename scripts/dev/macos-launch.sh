#!/usr/bin/env bash
#
# Voyager macOS 타겟 빌드 + 런치 스크립트.
# Zed/터미널/에이전트에서 동일한 Debug launch 경로를 사용한다.

set -euo pipefail

WORKSPACE="apps/macos/Voyager/Voyager.xcworkspace"
DERIVED_DATA="build/dev/DerivedData"
SOURCE_PACKAGES="build/dev/SourcePackages"
CONFIGURATION="Debug"
SCHEME=""
LAUNCH=1
ENV_VARS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCODEBUILD_CMD="${XCODEBUILD_CMD:-"$SCRIPT_DIR/xcodebuild-branch-product.sh"}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme)
      SCHEME="$2"; shift 2 ;;
    --configuration)
      CONFIGURATION="$2"; shift 2 ;;
    --workspace)
      WORKSPACE="$2"; shift 2 ;;
    --derived-data)
      DERIVED_DATA="$2"; shift 2 ;;
    --no-launch)
      LAUNCH=0; shift ;;
    --env)
      ENV_VARS+=("$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "알 수 없는 인자: $1" >&2
      exit 1 ;;
  esac
done

if [[ -z "$SCHEME" ]]; then
  echo "오류: --scheme 이 필요합니다." >&2
  exit 1
fi

WORKSPACE_ABS="$(cd "$(dirname "$WORKSPACE")" && pwd)/$(basename "$WORKSPACE")"
if [[ ! -d "$WORKSPACE_ABS" ]]; then
  echo "오류: 워크스페이스를 찾을 수 없습니다: $WORKSPACE_ABS" >&2
  exit 1
fi

LOG_DIR="build/dev"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/xcodebuild-${SCHEME}-${CONFIGURATION}.log"

echo "🔨 Building $SCHEME ($CONFIGURATION)..."
echo "   workspace: $WORKSPACE"
echo "   derivedDataPath: $DERIVED_DATA"

BUILD_ARGS=(
  -workspace "$WORKSPACE"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES"
  -skipPackagePluginValidation
  -skipMacroValidation
  COMPILER_INDEX_STORE_ENABLE=NO
  build
)

if command -v xcbeautify &>/dev/null || mise exec -- xcbeautify --version &>/dev/null 2>&1; then
  if command -v xcbeautify &>/dev/null; then
    XCBEAUTIFY="xcbeautify"
  else
    XCBEAUTIFY="mise exec -- xcbeautify"
  fi
  NSUnbufferedIO=YES "$XCODEBUILD_CMD" "${BUILD_ARGS[@]}" 2>&1 \
    | tee "$LOG_FILE" \
    | $XCBEAUTIFY --quiet
else
  NSUnbufferedIO=YES "$XCODEBUILD_CMD" "${BUILD_ARGS[@]}" 2>&1 | tee "$LOG_FILE"
fi

echo "✅ 빌드 완료: $SCHEME ($CONFIGURATION)"

if [[ "$LAUNCH" -eq 0 ]]; then
  echo "📦 --no-launch 지정: 런치하지 않고 종료."
  exit 0
fi

echo "🔍 빌드 산출물 경로 확인 중..."

SETTINGS_JSON=$("$XCODEBUILD_CMD" \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -showBuildSettings -json 2>/dev/null)

APP_DIR=$(printf '%s' "$SETTINGS_JSON" | python3 -c \
  "import sys,json; print(json.load(sys.stdin)[0]['buildSettings']['TARGET_BUILD_DIR'])")
WRAPPER=$(printf '%s' "$SETTINGS_JSON" | python3 -c \
  "import sys,json; print(json.load(sys.stdin)[0]['buildSettings']['WRAPPER_NAME'])")
EXEC_NAME=$(printf '%s' "$SETTINGS_JSON" | python3 -c \
  "import sys,json; print(json.load(sys.stdin)[0]['buildSettings']['EXECUTABLE_NAME'])")

APP_PATH="$APP_DIR/$WRAPPER"
EXEC_PATH="$APP_PATH/Contents/MacOS/$EXEC_NAME"

if [[ ! -x "$EXEC_PATH" ]]; then
  echo "오류: 실행파일을 찾을 수 없습니다: $EXEC_PATH" >&2
  echo "빌드는 성공했으나 산출물 경로 해석에 실패했을 수 있습니다." >&2
  exit 1
fi

echo "📦 App: $APP_PATH"

if [[ ${#ENV_VARS[@]} -gt 0 ]]; then
  echo "🔑 환경변수:"
  for ev in "${ENV_VARS[@]}"; do
    echo "   ${ev%%=*}"
  done
fi

echo "🚀 실행: $EXEC_NAME"
echo "   (종료하려면 Ctrl+C)"

if [[ ${#ENV_VARS[@]} -gt 0 ]]; then
  exec env "${ENV_VARS[@]}" "$EXEC_PATH"
else
  exec "$EXEC_PATH"
fi
