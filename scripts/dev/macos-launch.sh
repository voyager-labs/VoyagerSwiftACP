#!/usr/bin/env bash
#
# Voyager macOS 타겟 빌드 + 런치 스크립트
#
# Zed/터미널/에이전트에서 Xcode scheme 기반 macOS 앱·호스트·헬퍼를
# 동일한 방식으로 빌드하고 실행하기 위한 개발용 엔트리포인트다.
# Sweetpad(VSCode)의 Launch 태스크와 유사한 동작을 CLI로 재현한다:
#   1. xcodebuild 로 workspace 기반 빌드
#   2. -showBuildSettings -json 으로 .app 산출물 경로 해석
#   3. 환경변수를 주입하여 실행파일을 직접 실행 (LaunchServices 미경유)
#
# 사용법:
#   scripts/dev/macos-launch.sh \
#     --scheme Voyager-Dev \
#     --configuration Debug \
#     [--workspace <path>]   \
#     [--derived-data <path>] \
#     [--injection-next] \
#     [--no-launch] \
#     [--env KEY=VAL ...]
#
# 예시:
#   # Voyager Dev Debug 빌드 후 실행
#   scripts/dev/macos-launch.sh --scheme Voyager-Dev --configuration Debug \
#     --env VOYAGER_PROJECT_ROOT="$(pwd)"
#
#   # 빌드만 (런치하지 않음)
#   scripts/dev/macos-launch.sh --scheme Voyager-Dev --configuration Debug --no-launch

set -euo pipefail

# ─── 기본값 ────────────────────────────────────────────────
WORKSPACE="apps/macos/Voyager/Voyager.xcworkspace"
DERIVED_DATA=""
CONFIGURATION="Debug"
SCHEME=""
LAUNCH=1
INJECTION_NEXT=0
ENV_VARS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCODEBUILD_CMD="${XCODEBUILD_CMD:-"$SCRIPT_DIR/xcodebuild-branch-product.sh"}"

# ─── 인자 파싱 ─────────────────────────────────────────────
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
    --injection-next)
      INJECTION_NEXT=1; shift ;;
    --no-launch)
      LAUNCH=0; shift ;;
    --env)
      ENV_VARS+=("$2"); shift 2 ;;
    -h|--help)
      sed -n '3,/^$/p' "$0" | sed 's/^# \?//'
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

if [[ "$INJECTION_NEXT" -eq 1 ]]; then
  if [[ "$SCHEME" != "FileManagerHost-Dev" || "$CONFIGURATION" != "Debug" ]]; then
    echo "오류: --injection-next는 FileManagerHost-Dev Debug에서만 사용할 수 있습니다." >&2
    exit 1
  fi

  INJECTION_NEXT_APP="${INJECTION_NEXT_APP:-/Applications/InjectionNext.app}"
  if [[ ! -d "$INJECTION_NEXT_APP" ]]; then
    echo "오류: InjectionNext.app을 찾을 수 없습니다: $INJECTION_NEXT_APP" >&2
    exit 1
  fi

  INJECTION_PROJECT_ROOT="$(cd apps/macos && pwd)"
  export RUNNING_VIA_INJECTION_NEXT=1
  export INJECTION_PROJECT_ROOT
  ENV_VARS+=(
    "RUNNING_VIA_INJECTION_NEXT=1"
    "INJECTION_PROJECT_ROOT=$INJECTION_PROJECT_ROOT"
  )

  echo "💉 InjectionNext.app 실행"
  open "$INJECTION_NEXT_APP"
fi

WORKSPACE_ABS="$(cd "$(dirname "$WORKSPACE")" && pwd)/$(basename "$WORKSPACE")"
if [[ ! -d "$WORKSPACE_ABS" ]]; then
  echo "오류: 워크스페이스를 찾을 수 없습니다: $WORKSPACE_ABS" >&2
  exit 1
fi

# 로그 디렉토리 준비
LOG_DIR="build/dev"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/xcodebuild-${SCHEME}-${CONFIGURATION}.log"

# ─── 1단계: 빌드 ───────────────────────────────────────────
echo "🔨 Building $SCHEME ($CONFIGURATION)..."
echo "   workspace: $WORKSPACE"
if [[ -n "$DERIVED_DATA" ]]; then
  echo "   derivedDataPath: $DERIVED_DATA"
fi

BUILD_ARGS=()
BUILD_ARGS+=( -workspace "$WORKSPACE" )
BUILD_ARGS+=( -scheme "$SCHEME" )
BUILD_ARGS+=( -configuration "$CONFIGURATION" )
if [[ -n "$DERIVED_DATA" ]]; then
  BUILD_ARGS+=( -derivedDataPath "$DERIVED_DATA" )
fi
BUILD_ARGS+=( -skipPackagePluginValidation )
BUILD_ARGS+=( -skipMacroValidation )
BUILD_ARGS+=( COMPILER_INDEX_STORE_ENABLE=NO )
BUILD_ARGS+=( build )

  if [[ "$INJECTION_NEXT" -eq 1 ]]; then
    BUILD_ARGS+=(
      EMIT_FRONTEND_COMMAND_LINES=YES
      SWIFT_COMPILATION_MODE=incremental
    )
  fi

# xcbeautify 사용 가능하면 파이프, 아니면 원본 출력
if command -v xcbeautify &>/dev/null || mise exec -- xcbeautify --version &>/dev/null 2>&1; then
  # xcbeautify 경로 해석 (mise 관리일 수 있음)
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

# 빌드 실패 시 tee 파이프라인의 종료 코드를 확인
# (set -o pipefail 덕분에 자동 감지됨)
echo "✅ 빌드 완료: $SCHEME ($CONFIGURATION)"

# ─── 런치 생략 ─────────────────────────────────────────────
if [[ "$LAUNCH" -eq 0 ]]; then
  echo "📦 --no-launch 지정: 런치하지 않고 종료."
  exit 0
fi

# ─── 2단계: .app 경로 해석 ─────────────────────────────────
echo "🔍 빌드 산출물 경로 확인 중..."

SETTINGS_ARGS=()
SETTINGS_ARGS+=( -workspace "$WORKSPACE" )
SETTINGS_ARGS+=( -scheme "$SCHEME" )
SETTINGS_ARGS+=( -configuration "$CONFIGURATION" )
if [[ -n "$DERIVED_DATA" ]]; then
  SETTINGS_ARGS+=( -derivedDataPath "$DERIVED_DATA" )
fi
SETTINGS_ARGS+=( -showBuildSettings -json )
SETTINGS_JSON=$("$XCODEBUILD_CMD" "${SETTINGS_ARGS[@]}" 2>/dev/null)

# TARGET_BUILD_DIR / WRAPPER_NAME / EXECUTABLE_NAME 추출
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

# ─── 3단계: 환경변수 주입 후 실행 ──────────────────────────
if [[ ${#ENV_VARS[@]} -gt 0 ]]; then
  echo "🔑 환경변수:"
  for ev in "${ENV_VARS[@]}"; do
    # KEY=VAL 에서 KEY만 표시 (값은 민감할 수 있으므로 출력하지 않음)
    echo "   ${ev%%=*}"
  done
fi

echo "🚀 실행: $EXEC_NAME"
echo "   (종료하려면 Ctrl+C)"

# 환경변수를 적용하여 실행파일을 직접 실행
# exec 로 교체하여 터미널이 앱 프로세스에 직접 연결되도록 함
if [[ ${#ENV_VARS[@]} -gt 0 ]]; then
  exec env "${ENV_VARS[@]}" "$EXEC_PATH"
else
  exec "$EXEC_PATH"
fi
