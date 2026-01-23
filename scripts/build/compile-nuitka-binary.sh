#!/usr/bin/env bash
# Nuitka를 사용한 백엔드 바이너리 컴파일

# 사용: scripts/build/compile-nuitka-binary.sh
# 전제조건: venv가 이미 준비되어 있어야 함 (prepare-helper-runtime.sh 실행 필요)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

UV_BIN="${UV_BIN:-uv}"
BACKEND_DIR="${BACKEND_DIR:-${REPO_ROOT}/apps/backend}"
VENV_DIR="${VENV_DIR:-${BACKEND_DIR}/build/helper-runtime}"
NUITKA_OUTPUT_DIR="${NUITKA_OUTPUT_DIR:-${BACKEND_DIR}/build/nuitka}"
REGISTRY_JSON="${REPO_ROOT}/shared/system_property_registry.json"
CONDITION_REGISTRY_JSON="${REPO_ROOT}/shared/property_condition_registry.json"

log() {
  local level="${1:-INFO}"
  shift
  local timestamp
  timestamp="$(date '+%H:%M:%S')"
  printf "[%s] [compile-nuitka-binary] [%s] %s\n" "${timestamp}" "${level}" "$*" >&2
}

log_info() {
  log "INFO" "$@"
}

log_error() {
  log "ERROR" "$@"
}

command -v "${UV_BIN}" >/dev/null 2>&1 || {
  log_error "uv를 찾을 수 없습니다"
  log_error "  설치: curl -LsSf https://astral.sh/uv/install.sh | sh"
  log_error "  또는 UV_BIN 환경변수로 경로 지정: UV_BIN=/path/to/uv $0"
  exit 1
}

VENV_PYTHON="${VENV_DIR}/bin/python"
if [[ ! -x "${VENV_PYTHON}" ]]; then
  log_error "venv Python을 찾을 수 없습니다: ${VENV_PYTHON}"
  log_error "  먼저 prepare-helper-runtime.sh를 실행하여 venv를 준비하세요"
  exit 1
fi

SERVER_SCRIPT="${BACKEND_DIR}/src/app/server.py"
if [[ ! -f "${SERVER_SCRIPT}" ]]; then
  log_error "server.py를 찾을 수 없습니다: ${SERVER_SCRIPT}"
  exit 1
fi

BINARY_NAME="Voyager Backend"
RAW_BINARY_PATH="${NUITKA_OUTPUT_DIR}/server.dist/server.bin"
BINARY_PATH="${NUITKA_OUTPUT_DIR}/server.dist/${BINARY_NAME}"
BUILD_CACHE_FILE="${NUITKA_OUTPUT_DIR}/.build_cache"

EXISTING_BINARY_PATH=""
if [[ -f "${BINARY_PATH}" ]]; then
  EXISTING_BINARY_PATH="${BINARY_PATH}"
elif [[ -f "${RAW_BINARY_PATH}" ]]; then
  EXISTING_BINARY_PATH="${RAW_BINARY_PATH}"
fi

# 증분 빌드 체크: 환경 변수로 강제 재빌드 가능
FORCE_REBUILD="${FORCE_REBUILD:-0}"
if [[ "${FORCE_REBUILD}" == "1" ]]; then
  log_info "강제 재빌드 모드 (FORCE_REBUILD=1)"
  rm -rf "${NUITKA_OUTPUT_DIR}"
elif [[ -n "${EXISTING_BINARY_PATH}" ]]; then
  # 바이너리가 존재하면 소스 변경 여부 확인
  log_info "기존 바이너리 발견, 소스 변경 여부 확인 중..."
  
  # 소스 디렉토리의 최신 수정 시간 확인
  SOURCE_DIR="${BACKEND_DIR}/src"
  LATEST_SOURCE_TIME=$(find "${SOURCE_DIR}" -type f -name "*.py" -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1)
  BINARY_TIME=$(stat -f "%m" "${EXISTING_BINARY_PATH}" 2>/dev/null || echo "0")
  CACHE_TIME=$(stat -f "%m" "${BUILD_CACHE_FILE}" 2>/dev/null || echo "0")
  
  # pyproject.toml도 확인 (의존성 변경 시)
  PYPROJECT_TIME=$(stat -f "%m" "${BACKEND_DIR}/pyproject.toml" 2>/dev/null || echo "0")
  LATEST_SOURCE_TIME=$((LATEST_SOURCE_TIME > PYPROJECT_TIME ? LATEST_SOURCE_TIME : PYPROJECT_TIME))
  
  if [[ -n "${LATEST_SOURCE_TIME}" ]] && [[ "${LATEST_SOURCE_TIME}" -le "${BINARY_TIME}" ]] && [[ "${LATEST_SOURCE_TIME}" -le "${CACHE_TIME}" ]]; then
    log_info "소스 변경 없음, 기존 바이너리 사용 (스킵)"
    log_info "바이너리 경로: ${EXISTING_BINARY_PATH}"
    exit 0
  else
    log_info "소스 변경 감지, 재빌드 필요"
  fi
fi

log_info "Nuitka 빌드 시작 (출력 디렉토리: ${NUITKA_OUTPUT_DIR})"
mkdir -p "${NUITKA_OUTPUT_DIR}"

MACOS_SDK_PATH=$(xcodebuild -version -sdk macosx Path 2>/dev/null | head -1)
if [[ -z "${MACOS_SDK_PATH}" ]]; then
  log_error "macOS SDK 경로를 찾을 수 없습니다. Xcode Command Line Tools가 설치되어 있는지 확인하세요."
  exit 1
fi

export SDKROOT="${MACOS_SDK_PATH}"
log_info "Nuitka 빌드 실행 (Python: ${VENV_PYTHON}, SDK: ${MACOS_SDK_PATH})"

# arm64 전용 빌드 (빌드 시간 단축을 위해 universal 바이너리는 제외)
MIGRATIONS_DIR="${BACKEND_DIR}/src/infra/db/migrations"
OSX_METADATA_DATA_DIR="${BACKEND_DIR}/src/osxmetadata/attribute_data"
if [[ ! -f "${REGISTRY_JSON}" ]]; then
  log_error "레지스트리 JSON을 찾을 수 없습니다: ${REGISTRY_JSON}"
  exit 1
fi
if [[ ! -f "${CONDITION_REGISTRY_JSON}" ]]; then
  log_error "레지스트리 JSON을 찾을 수 없습니다: ${CONDITION_REGISTRY_JSON}"
  exit 1
fi
if ! "${UV_BIN}" run --directory "${BACKEND_DIR}" --python "${VENV_PYTHON}" nuitka \
  --standalone \
  --macos-target-arch="arm64" \
  --output-dir="${NUITKA_OUTPUT_DIR}" \
  --include-data-dir="${BACKEND_DIR}/src/infra/db=infra/db" \
  --include-data-dir="${OSX_METADATA_DATA_DIR}=osxmetadata/attribute_data" \
  --include-data-files="${REGISTRY_JSON}=shared/system_property_registry.json" \
  --include-data-files="${CONDITION_REGISTRY_JSON}=shared/property_condition_registry.json" \
  --include-data-files="${MIGRATIONS_DIR}/env.py=infra/db/migrations/env.py" \
  --include-data-files="${MIGRATIONS_DIR}/config.py=infra/db/migrations/config.py" \
  --include-data-files="${MIGRATIONS_DIR}/__init__.py=infra/db/migrations/__init__.py" \
  --include-data-files="${MIGRATIONS_DIR}/versions/__init__.py=infra/db/migrations/versions/__init__.py" \
  --include-data-files="${MIGRATIONS_DIR}/versions/*.py=infra/db/migrations/versions/" \
  --include-package=langchain_core \
  --include-package=langchain_community \
  --include-package=langchain_openai \
  --remove-output \
  --assume-yes-for-downloads \
  "${SERVER_SCRIPT}"; then
  log_error "Nuitka 빌드 실패"
  exit 1
fi

if [[ -f "${RAW_BINARY_PATH}" ]]; then
  mv -f "${RAW_BINARY_PATH}" "${BINARY_PATH}"
fi

if [[ -f "${BINARY_PATH}" ]]; then
  log_info "빌드 완료: ${BINARY_PATH}"
  ls -lh "${BINARY_PATH}"
  
  # 빌드 캐시 파일 생성 (성공한 빌드 타임스탬프 기록)
  touch "${BUILD_CACHE_FILE}"
  log_info "빌드 캐시 업데이트: ${BUILD_CACHE_FILE}"
else
  log_error "빌드 실패: 바이너리를 찾을 수 없습니다"
  exit 1
fi

log_info "완료. 바이너리 경로: ${BINARY_PATH}"
