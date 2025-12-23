#!/usr/bin/env bash
# 백엔드 휠을 빌드하고 번들용 venv에 설치해 리소스로 복사할 수 있게 준비합니다.
# - UV_BIN: uv 실행 파일 경로(기본 uv)
# - BACKEND_DIR: 백엔드 루트(기본 <repo>/apps/backend)
# - VENV_DIR: 생성될 venv 경로(기본 <BACKEND_DIR>/build/helper-runtime)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

UV_BIN="${UV_BIN:-uv}"
BACKEND_DIR="${BACKEND_DIR:-${REPO_ROOT}/apps/backend}"
DIST_DIR="${DIST_DIR:-${BACKEND_DIR}/dist}"
VENV_DIR="${VENV_DIR:-${BACKEND_DIR}/build/helper-runtime}"
PYTHON_VERSION_FILE="${PYTHON_VERSION_FILE:-${BACKEND_DIR}/.python-version}"
REQUIRED_UV_VERSION="${REQUIRED_UV_VERSION:-0.8.13}"
required_python_version=""

log() {
  local level="${1:-INFO}"
  shift
  local timestamp
  timestamp="$(date '+%H:%M:%S')"
  printf "[%s] [prepare-helper-runtime] [%s] %s\n" "${timestamp}" "${level}" "$*" >&2
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

if [[ -n "${REQUIRED_UV_VERSION}" ]]; then
  uv_version="$("${UV_BIN}" --version | awk '{print $2}')"
  if [[ "${uv_version}" != "${REQUIRED_UV_VERSION}" ]]; then
    log_error "uv 버전 불일치: 현재 ${uv_version}, 요구 ${REQUIRED_UV_VERSION}"
    log_error "  설치: curl -LsSf https://astral.sh/uv/install.sh | sh"
    log_error "  또는 REQUIRED_UV_VERSION을 맞춰주세요"
    exit 1
  fi
fi

if [[ -f "${PYTHON_VERSION_FILE}" ]]; then
  required_python_version="$(tr -d ' \t\r\n' < "${PYTHON_VERSION_FILE}")"
  if [[ -n "${required_python_version}" ]]; then
    export UV_PYTHON="${required_python_version}"
  fi
fi

if [[ -n "${required_python_version}" ]]; then
  python_version="$("${UV_BIN}" run python -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
  if [[ "${python_version}" != "${required_python_version}" ]]; then
    log_error "python 버전 불일치: 현재 ${python_version}, 요구 ${required_python_version}"
    log_error "  ${PYTHON_VERSION_FILE}을 갱신하거나 UV_PYTHON 환경변수를 지정하세요"
    exit 1
  fi
fi

if [[ ! -f "${BACKEND_DIR}/uv.lock" ]]; then
  log_error "uv.lock이 없습니다. 먼저 uv.lock을 생성해주세요 (예: cd apps/backend && uv lock)"
  exit 1
fi

log_info "백엔드 휠 빌드 시작 (출력 디렉토리: ${DIST_DIR})"
mkdir -p "${DIST_DIR}"
if ! (cd "${BACKEND_DIR}" && "${UV_BIN}" build --wheel --out-dir "${DIST_DIR}"); then
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
# 번들 내 파이썬 이식성을 위해 복사 모드 사용
"${UV_BIN}" run python -m venv --copies --without-pip "${VENV_DIR}"

log_info "uv Python 런타임(lib) 복사"
python_base_prefix="$("${UV_BIN}" run python -c 'import sys; print(sys.base_prefix)')"
if [[ -z "${python_base_prefix}" ]]; then
  log_error "uv Python base prefix를 확인할 수 없습니다"
  exit 1
fi
if [[ ! -d "${python_base_prefix}/lib" ]]; then
  log_error "uv Python lib 디렉토리를 찾을 수 없습니다: ${python_base_prefix}/lib"
  exit 1
fi
rsync -a "${python_base_prefix}/lib/" "${VENV_DIR}/lib/"

log_info "requirements.txt 내보내기 (uv.lock -> requirements.txt, 프로젝트 패키지 제외)"
req_file="$(mktemp)"
if ! (cd "${BACKEND_DIR}" && "${UV_BIN}" export --format requirements.txt --locked --no-dev --no-emit-project --output-file "${req_file}"); then
  log_error "uv export 실패. requirements.txt를 생성할 수 없습니다"
  rm -f "${req_file}"
  exit 1
fi

log_info "venv에 빌드 도구 설치 (setuptools, wheel)"
if ! "${UV_BIN}" pip install --python "${VENV_DIR}/bin/python" --no-build-isolation setuptools wheel; then
  log_error "빌드 도구 설치 실패"
  exit 1
fi

log_info "venv에 런타임 의존성 설치"
if ! "${UV_BIN}" pip install --python "${VENV_DIR}/bin/python" --no-build-isolation -r "${req_file}"; then
  log_error "런타임 의존성 설치 실패 (${req_file})"
  rm -f "${req_file}"
  exit 1
fi
rm -f "${req_file}"

# 휠은 항상 재설치 (최신 코드 반영)
log_info "venv에 백엔드 휠 설치/업데이트"
"${UV_BIN}" pip install --python "${VENV_DIR}/bin/python" --no-deps --reinstall "${wheel_path}"

log_info "완료. venv 경로: ${VENV_DIR}"
log_info "리소스 복사 예시: ditto \"${VENV_DIR}\" \"Voyager.app/Contents/Resources/helper-runtime\""
