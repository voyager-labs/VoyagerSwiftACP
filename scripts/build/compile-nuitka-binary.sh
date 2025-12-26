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

log_info "Nuitka 빌드 시작 (출력 디렉토리: ${NUITKA_OUTPUT_DIR})"
mkdir -p "${NUITKA_OUTPUT_DIR}"

MACOS_SDK_PATH=$(xcodebuild -version -sdk macosx Path 2>/dev/null | head -1)
if [[ -z "${MACOS_SDK_PATH}" ]]; then
  log_error "macOS SDK 경로를 찾을 수 없습니다. Xcode Command Line Tools가 설치되어 있는지 확인하세요."
  exit 1
fi

export SDKROOT="${MACOS_SDK_PATH}"
log_info "Nuitka 빌드 실행 (Python: ${VENV_PYTHON}, SDK: ${MACOS_SDK_PATH})"

# 백엔드 디렉토리에서 uv run 실행 (pyproject.toml의 nuitka 의존성 사용)
# NOTE: --include-data-dir은 .py 파일을 제외하므로, Alembic 마이그레이션에 필요한
# Python 파일들은 --include-data-files로 명시적으로 포함해야 함
MIGRATIONS_DIR="${BACKEND_DIR}/src/infra/db/migrations"
if ! "${UV_BIN}" run --directory "${BACKEND_DIR}" --python "${VENV_PYTHON}" nuitka \
  --standalone \
  --output-dir="${NUITKA_OUTPUT_DIR}" \
  --include-data-dir="${BACKEND_DIR}/src/app/config=app/config" \
  --include-data-dir="${BACKEND_DIR}/src/infra/db=infra/db" \
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

BINARY_PATH="${NUITKA_OUTPUT_DIR}/server.dist/server.bin"
if [[ -f "${BINARY_PATH}" ]]; then
  log_info "빌드 완료: ${BINARY_PATH}"
  ls -lh "${BINARY_PATH}"
else
  log_error "빌드 실패: 바이너리를 찾을 수 없습니다"
  exit 1
fi

log_info "완료. 바이너리 경로: ${BINARY_PATH}"

