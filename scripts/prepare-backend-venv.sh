#!/usr/bin/env bash
# 백엔드 휠을 빌드하고 번들용 venv에 설치해 리소스로 복사할 수 있게 준비합니다.
# - UV_BIN: uv 실행 파일 경로(기본 uv)
# - PYTHON_BIN: venv 생성에 사용할 파이썬(기본 python3)
# - BACKEND_DIR: 백엔드 루트(기본 <repo>/apps/backend)
# - VENV_DIR: 생성될 venv 경로(기본 <BACKEND_DIR>/build/backend-venv)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

UV_BIN="${UV_BIN:-uv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
BACKEND_DIR="${BACKEND_DIR:-${REPO_ROOT}/apps/backend}"
DIST_DIR="${DIST_DIR:-${BACKEND_DIR}/dist}"
VENV_DIR="${VENV_DIR:-${BACKEND_DIR}/build/backend-venv}"
UV_CACHE_DIR="${UV_CACHE_DIR:-${BACKEND_DIR}/.uvcache}"

log() {
  local level="${1:-INFO}"
  shift
  local timestamp
  timestamp="$(date '+%H:%M:%S')"
  printf "[%s] [prepare-backend-venv] [%s] %s\n" "${timestamp}" "${level}" "$*" >&2
}

log_info() {
  log "INFO" "$@"
}

log_error() {
  log "ERROR" "$@"
}

export UV_CACHE_DIR
mkdir -p "${UV_CACHE_DIR}"

command -v "${UV_BIN}" >/dev/null 2>&1 || {
  log_error "uv를 찾을 수 없습니다"
  log_error "  설치: curl -LsSf https://astral.sh/uv/install.sh | sh"
  log_error "  또는 UV_BIN 환경변수로 경로 지정: UV_BIN=/path/to/uv $0"
  exit 1
}

command -v "${PYTHON_BIN}" >/dev/null 2>&1 || {
  log_error "python을 찾을 수 없습니다"
  log_error "  설치: brew install python"
  log_error "  또는 PYTHON_BIN 환경변수로 경로 지정: PYTHON_BIN=/path/to/python $0"
  exit 1
}

if [[ ! -f "${BACKEND_DIR}/uv.lock" ]]; then
  log_info "uv.lock이 없습니다. uv sync 실행하여 생성합니다"
  if ! (cd "${BACKEND_DIR}" && "${UV_BIN}" sync); then
    log_error "uv sync 실패. uv.lock을 생성할 수 없습니다"
    exit 1
  fi
  log_info "uv.lock 생성 완료"
fi

log_info "백엔드 휠 빌드 시작 (출력 디렉토리: ${DIST_DIR})"
mkdir -p "${DIST_DIR}"
if ! (cd "${BACKEND_DIR}" && "${UV_BIN}" build --wheel --outdir "${DIST_DIR}"); then
  log_error "uv build 실패. 프로젝트 설정 및 의존성을 확인하세요"
  exit 1
fi

wheel_path="$(ls "${DIST_DIR}"/voyager_app_backend-*.whl 2>/dev/null | sort | tail -n 1 || true)"
if [[ -z "${wheel_path}" ]]; then
  log_error "빌드된 휠을 찾을 수 없습니다 (${DIST_DIR}/*.whl 확인 필요)"
  exit 1
fi
log_info "빌드된 휠: ${wheel_path}"

log_info "기존 venv 정리 후 재생성 (${VENV_DIR})"
rm -rf "${VENV_DIR}"
"${PYTHON_BIN}" -m venv "${VENV_DIR}"

log_info "requirements.txt 내보내기 (uv.lock -> requirements.txt, 프로젝트 패키지 제외)"
req_file="$(mktemp)"
if ! (cd "${BACKEND_DIR}" && "${UV_BIN}" export --format requirements.txt --locked --no-dev --no-emit-project --output-file "${req_file}"); then
  log_error "uv export 실패. requirements.txt를 생성할 수 없습니다"
  rm -f "${req_file}"
  exit 1
fi

log_info "pip 최신화"
"${VENV_DIR}/bin/pip" install --upgrade pip
# 빌드 도구 최신화 (--no-build-isolation 사용 시 필요)
"${VENV_DIR}/bin/pip" install --upgrade setuptools wheel

log_info "venv에 런타임 의존성 설치"
if ! "${VENV_DIR}/bin/pip" install --no-build-isolation -r "${req_file}"; then
  log_error "런타임 의존성 설치 실패 (${req_file})"
  rm -f "${req_file}"
  exit 1
fi
rm -f "${req_file}"

# 휠은 항상 재설치 (최신 코드 반영)
log_info "venv에 백엔드 휠 설치/업데이트 (의존성 재사용)"
"${VENV_DIR}/bin/pip" install --no-deps --force-reinstall "${wheel_path}"

log_info "완료. venv 경로: ${VENV_DIR}"
log_info "리소스 복사 예시: ditto \"${VENV_DIR}\" \"<앱>.app/Contents/Resources/backend-venv\""
