# 개발 및 배포

## 로컬 개발 절차

- Backend 설치: `cd apps/backend && uv sync && uv run pre-commit install`
- Backend 개발 서버: `uv run dev`
- Backend prod 유사: `uv run prod`
- macOS 앱:
  - GUI: `apps/macos/Voyager/Voyager.xcodeproj` 열기
  - CLI 빌드: `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug`
  - 배포/Archive: `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Prod -configuration Release`

환경

- 저장소 루트의 `.env.example`; 실제 `.env`가 있으면 macOS 헬퍼가 PATH/UV_CMD 등을 주입

예시 환경변수 (로컬)

- `APP_ENV=development`
- `BACKEND_DIR=apps/backend`
- `VOYAGER_PATH=/Users/you/Projects/voyager-app`
- `VOYAGER_LOG_FILE=.logs/backend-dev.log`

## Local Run Guide (End-to-End)

1) Backend 준비

- `cd apps/backend && uv sync && uv run pre-commit install`
- 개발 서버: `uv run dev` (콘솔에서 lifespan 로그에 DB 초기화/Alembic 적용 여부 확인)
- 헬스체크: `curl -s http://127.0.0.1:8000/` (또는 FastAPI 자동 문서 `http://127.0.0.1:8000/docs`)

2) macOS 앱 실행

- GUI: `apps/macos/Voyager/Voyager.xcodeproj` 열기
- 또는 CLI 빌드: `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug`

3) 연동 확인

- 앱에서 Dock 호출 → 간단한 질의 입력 → 백엔드 로그에서 `/search` 요청/응답 확인
- 실패 시: `BackendManager*.swift` 로그 확인

1) 기본 트러블슈팅

- `uv` 미발견: PATH에 `uv` 설치/노출 필요
- SQLite 잠금: 인덱싱 중 동시 접근 회피, 재시도 로직/백오프 확인
- macOS 권한: 접근 불가 경로는 가드 처리 및 UX 안내

## 빌드/배포

- 백엔드는 `pyproject.toml`에 정의된 CLI 스크립트로 uvicorn 구동
- macOS 앱은 런치 시 헬퍼를 통해 백엔드를 자동 기동 가능

### Release 빌드: 번들용 백엔드 venv 준비

Release 빌드 시 자동으로 번들용 백엔드 venv가 준비됩니다:

1. **VoyagerHelper 빌드 단계**에서 `scripts/prepare-backend-venv.sh` 실행
   - 백엔드 휠 빌드 (`uv build --wheel`)
   - 번들용 venv 생성 (`apps/backend/build/backend-venv`)
   - uv.lock에서 런타임 의존성 추출 및 설치
   - 빌드된 백엔드 휠을 venv에 설치

2. **"Bundle Backend Venv" 빌드 단계**에서 venv를 앱 번들로 복사
   - `apps/backend/build/backend-venv` → `VoyagerHelper.app/Contents/Resources/backend-venv`
   - Release 빌드에서만 실행 (Debug 빌드는 스킵)

3. **앱 실행 시** 번들된 venv 사용
   - Release 빌드: 번들 리소스의 `backend-venv/bin/python` 사용
   - Debug 빌드: 로컬 `uv` 환경 사용

**참고:**
- Debug 빌드에서는 venv 준비를 스킵하고 로컬 개발 환경(`uv`)을 사용합니다
- Release 빌드에서만 독립형 앱 번들을 위해 venv가 번들에 포함됩니다

## 보안/인증(로컬 개발)

- 로컬 개발 단계에서는 인증을 적용하지 않습니다. 보호 라우트가 필요한 시점에 인증 프레임워크(예: 헤더 토큰)를 사전 구성 후 활성화합니다.

## 미들웨어/로깅

- 요청/응답에 대한 구조화 로깅을 선택적으로 도입할 수 있습니다(uvicorn 로거 + 간단 미들웨어). 초기 단계에서는 기본 로그로 충분합니다.

## Observability & Monitoring

- Metrics (초기)
  - API: 요청 지연 p50/p95, 에러율(4xx/5xx), 처리량
  - 인덱싱: 배치 처리량, 실패율, 큐 길이(도입 시)
- Logging (구조화 권장)
  - 공통 필드: `level`, `route`, `method`, `status`, `duration_ms`, `error_code`, `trace_id`
  - 에러 경로: 스택 요약 + 상기 필드 포함, PII/경로 마스킹 적용
- 계측 포인트(최소)
  - FastAPI 미들웨어: 요청 시작/종료 시 타이밍 측정 및 로그 기록
  - 예외 핸들러: 표준 에러 페이로드 + 로그 기록
  - 인덱싱 실행부: 작업 시작/완료/실패 카운트 및 소요 시간
- 프라이버시
  - 파일 경로/사용자 입력 등 민감 정보는 로그에 직접 남기지 않음(요약/해시/마스킹)
  - 외부 전송 금지, 로컬 개발 환경 한정 출력(운영 시 별도 싱크 설계)
