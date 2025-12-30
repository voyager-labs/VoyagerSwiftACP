# 개발 및 배포

## 로컬 개발 절차

- Backend 설치: `cd apps/backend && uv sync && uv run pre-commit install`
- Backend 개발 서버: `uv run dev`
- Backend 프로덕션 모드 테스트: `uv run prod`
- macOS 앱:
  - GUI: `apps/macos/Voyager/Voyager.xcodeproj` 열기
  - CLI 빌드: `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug`
  - 배포/Archive: `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Prod -configuration Release`

## 빌드 스킴 및 환경 설정

### 스킴과 빌드 설정

프로젝트는 두 가지 스킴을 제공합니다:

| 스킴 | 빌드 설정 | APP_ENV | BACKEND_MODE | 백엔드 실행 방식 |
|------|-----------|---------|--------------|------------------|
| `Voyager-Dev` | Debug | `dev` (자동) | `source` (자동) | 로컬 `uv` (`uv run dev`) |
| `Voyager-Prod` | Release | `prod` (자동) | `bundled` (자동) | 번들 바이너리 (`server/server.bin`) |

### 스킴 × 빌드 설정 매트릭스

공유 스킴 기본값은 아래 2개 조합입니다:

- `Voyager-Dev` + Debug
- `Voyager-Prod` + Release

하지만 스킴(backend mode)과 빌드 설정(APP_ENV)은 독립 축이라, 아래 4가지 조합으로도 설명할 수 있습니다.

| 스킴 | 빌드 설정 | APP_ENV | BACKEND_MODE | 백엔드 실행 |
|------|-----------|---------|---------------------|-------------|
| Dev  | Debug     | dev     | source              | `uv run dev` |
| Dev  | Release   | prod    | source              | `uv run prod` |
| Prod | Debug     | dev     | bundled             | `server/server.bin` |
| Prod | Release   | prod    | bundled             | `server/server.bin` |

### 환경 자동 감지

앱은 다음 순서로 환경을 감지합니다:

1. **Info.plist의 `APP_ENV`** (빌드 설정에서 자동 주입)
   - Debug 빌드: `APP_ENV=dev`
   - Release 빌드: `APP_ENV=prod`
2. **기본값**: `dev`

### 백엔드 실행 방식 감지

백엔드 실행 방식은 다음 순서로 결정됩니다:

1. **스킴 환경변수 `BACKEND_MODE`** (Xcode Run 시 자동 주입)
   - `*-Dev` 스킴: `BACKEND_MODE=source`
   - `*-Prod` 스킴: `BACKEND_MODE=bundled`
2. **번들 리소스 확인**: `server` 디렉토리 존재 여부
3. **기본값**: `source`

### 환경 파일

- **`.env.dev`** (Git ignored): 로컬 개발 환경
  - Debug 빌드에서 사용
  - 비밀키 포함 가능
  - 생성: `cp .env.example .env.dev`
- **`.env.prod`** (Git tracked): 프로덕션 환경 템플릿
  - Release 빌드에서 사용
  - 비밀키 제외, CI/CD에서 주입

### 예시 환경변수 (로컬 `.env.dev`)

- `PUBLIC_BACKEND_HOST=127.0.0.1`
- `PUBLIC_BACKEND_PORT=0` (0이면 동적 할당)
- `OPENAI_API_KEY=...` (로컬 개발용)

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
- 실패 시: VoyagerHelper(stderr) 로그 및 `ProcessRunner` 실행 로그 확인

1) 기본 트러블슈팅

- `uv` 미발견: PATH에 `uv` 설치/노출 필요
- SQLite 잠금: 인덱싱 중 동시 접근 회피, 재시도 로직/백오프 확인
- macOS 권한: 접근 불가 경로는 가드 처리 및 UX 안내

## 빌드/배포

- 백엔드는 `pyproject.toml`에 정의된 CLI 스크립트로 uvicorn 구동
- macOS 앱은 런치 시 헬퍼를 통해 백엔드를 자동 기동 가능

### 빌드 프로세스 상세

#### Debug 빌드 (Dev 스킴)

1. **빌드 설정**: Debug
2. **APP_ENV**: `dev` (자동 설정)
3. **BACKEND_MODE**: `source` (스킴에서 자동 주입)
4. **백엔드 venv 준비**: 스킵 (로컬 `uv` 사용)
5. **백엔드 바이너리 빌드**: 스킵
6. **환경 파일**: `.env.dev` 로드 (프로젝트 루트)
7. **백엔드 실행**: `apps/backend`에서 `uv run dev` 실행

#### Release 빌드 (Prod 스킴)

1. **빌드 설정**: Release
2. **APP_ENV**: `prod` (자동 설정)
3. **BACKEND_MODE**: `bundled` (스킴에서 자동 주입)
4. **백엔드 바이너리 빌드** (`Build Backend Binary` 빌드 단계):
   - `scripts/build/build-backend-binary.sh` 실행
   - `scripts/build/prepare-helper-runtime.sh`: 백엔드 venv 준비 (의존성 설치)
   - `scripts/build/compile-nuitka-binary.sh`: Nuitka로 arm64 바이너리 컴파일
     - `--standalone` 바이너리 생성
     - `--include-package`로 동적 import 패키지 포함
     - arm64 전용 빌드 (빌드 시간 단축을 위해 universal 바이너리 제외)
   - `apps/backend/build/nuitka/server.dist` → `VoyagerHelper.app/Contents/Resources/server` 복사
   - `.env.prod` 파일을 번들 리소스로 복사
   - 바이너리 서명 (코드사인)
5. **환경 파일**: `.env.prod` 로드 (번들 리소스 우선, 없으면 프로젝트 루트)
6. **백엔드 실행**: 번들된 `server/server.bin` 직접 실행

**참고:**
- Debug 빌드에서는 백엔드 바이너리 빌드를 스킵하고 로컬 개발 환경(`uv`)을 사용합니다
- Release 빌드에서만 독립형 앱 번들을 위해 Nuitka 바이너리가 번들에 포함됩니다
- 환경 감지는 빌드 설정과 스킴에 따라 자동으로 이루어지므로 수동 설정이 필요 없습니다
- 빌드 시간 단축을 위해 arm64 전용으로 빌드합니다 (universal 바이너리는 제외)

## 보안/인증(로컬 개발)

- 로컬 개발 단계에서는 인증을 적용하지 않습니다. 보호 라우트가 필요한 시점에 인증 프레임워크(예: 헤더 토큰)를 사전 구성 후 활성화합니다.

## 미들웨어/로깅

- 요청/응답에 대한 구조화 로깅을 선택적으로 도입할 수 있습니다(uvicorn 로거 + 간단 미들웨어). 초기 단계에서는 기본 로그로 충분합니다.

## CI/CD (GitHub Actions)

Release 빌드 및 DMG 패키징은 GitHub Actions에서 자동화되어 있습니다:

### 트리거

- `v*` 태그 푸시 시 자동 실행
- `workflow_dispatch`로 수동 실행 가능

### 필요한 GitHub Secrets

| Secret | 설명 |
|--------|------|
| `APPLE_CERTIFICATE_BASE64` | .p12 인증서 (base64 인코딩) |
| `APPLE_CERTIFICATE_PASSWORD` | 인증서 비밀번호 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID (notarization용) |
| `APPLE_APP_SPECIFIC_PASSWORD` | 앱 전용 비밀번호 (notarization용) |
| `OPENAI_API_KEY` | OpenAI API 키 (prod 환경용, `.env.prod`에 주입됨) |
| `OPENAI_ORG_ID` | OpenAI Organization ID (선택적, `.env.prod`에 주입됨) |
| `OPENAI_PROJECT` | OpenAI Project ID (선택적, `.env.prod`에 주입됨) |

### 빌드 프로세스

1. Python 3.13 + uv 설치
2. `build-backend-binary.sh`로 백엔드 Nuitka 바이너리 빌드
   - `prepare-helper-runtime.sh`: 백엔드 venv 준비 (의존성 설치)
   - `compile-nuitka-binary.sh`: Nuitka로 arm64 바이너리 컴파일
3. `.env.prod` 복사 (secrets 없음)
   - Git에 추적된 `.env.prod` 파일을 빌드 디렉토리로 복사
   - Secrets는 파일에 포함하지 않음 (앱 번들에 노출 방지)
   - Secrets는 환경 변수나 다른 보안 메커니즘으로 전달 필요
4. Apple 인증서 설치 (임시 키체인)
5. `xcodebuild`로 Release 빌드
6. DMG 생성 및 서명
7. Notarization (Apple 인증)
8. GitHub Release 생성 (태그 빌드 시)

## 코드사이닝 및 Entitlements

### Bundle ID

| 타겟 | Bundle ID |
|-----|-----------|
| Voyager (메인 앱) | `fm.voyager.Voyager` |
| VoyagerHelper | `fm.voyager.VoyagerHelper` |

### Entitlements 구성

**Debug 빌드:**
- `com.apple.security.get-task-allow`: true (디버거 허용)
- App Sandbox: 비활성화

**Release 빌드:**
- `com.apple.security.get-task-allow`: false
- `com.apple.security.app-sandbox`: true
- `com.apple.security.inherit`: true (VoyagerHelper, 자식 프로세스 sandbox 상속)
- `com.apple.security.network.server`: true (VoyagerHelper)
- `com.apple.security.network.client`: true
- `com.apple.security.files.user-selected.read-write`: true

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
