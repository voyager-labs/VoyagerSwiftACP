# 환경 설정 (ENV)

Voyager는 macOS 앱/Helper/XPC와 서버 백엔드를 분리된 런타임으로 운영합니다.
환경 값은 기본적으로 `.env` 파일 + 런타임 환경 변수의 조합으로 구성됩니다.

## 1. 로딩 전략

### 1.1 macOS (Voyager / VoyagerHelper / FilterSearchXPC)

macOS 쪽은 `EnvironmentLoader.loadEnvFiles()`를 통해 환경 파일을 로드합니다.

- `APP_ENV`: `dev` 또는 `prod`
- 로드 대상: `.env.{APP_ENV}`

로드 순서

1) project root 우선(`VOYAGER_PROJECT_ROOT` 또는 자동 추론)
2) bundle resources fallback

관련 코드

- `apps/macos/Voyager/Shared/EnvironmentLoader.swift`

### 1.2 Backend (FastAPI)

백엔드는 `app.config.load_env()`에서 `.env.{APP_ENV}`를 로드합니다.

- 로딩 우선순위는 **프로세스 환경 변수 > `.env.{APP_ENV}`** 입니다.
- `.env` 로딩은 `override=False`이므로, 먼저 설정된 값이 우선합니다.

관련 코드

- `apps/backend/src/app/config.py`

## 2. 핵심 키 맵

### 2.1 App / UI

- `PUBLIC_APP_NAME`
- `PUBLIC_HELPER_NAME`
- `PUBLIC_LOG_LEVEL`

### 2.2 Gateway / Web

- `PUBLIC_GATEWAY_URL`
- `PUBLIC_WEB_BASE_URL`

### 2.3 SQLite

- `PUBLIC_SQLITE_PROTOCOL`
- `PUBLIC_SQLITE_ECHO`
- `PUBLIC_SQLITE_CHECK_SAME_THREAD`
- `PUBLIC_SQLITE_FILE_LOCATION`
- `PUBLIC_SQLITE_FILE_NAME`

관련 코드

- `apps/backend/src/app/config.py`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`

### 2.4 Observability (Sentry)

- `PUBLIC_SENTRY_DSN` (없으면 Sentry 비활성)
- `PUBLIC_SENTRY_TRACES_SAMPLE_RATE`

관련 코드

- `apps/macos/Voyager/Shared/Logging/SentryBootstrap.swift`

### 2.5 Indexing 튜닝

초기 인덱싱 recovery 동작은 다음 키로 튜닝할 수 있습니다.

- `VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS`
- `VOYAGER_INITIAL_INDEXING_MAX_RETRIES`
- `VOYAGER_INITIAL_INDEXING_MIN_RETRY_INTERVAL_SECONDS`
- `VOYAGER_INITIAL_INDEXING_HEARTBEAT_INTERVAL_SECONDS`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRecovery.swift`

## 3. 파일별 역할

레포 루트에 기본 템플릿이 존재합니다.

- `.env.dev` (Git ignored): 로컬 개발 환경 (시크릿 포함 가능)
- `.env.prod` (Git tracked): 프로덕션용 PUBLIC 설정/템플릿 (시크릿 금지)
- `.env.example`: 키 목록 참고용

## 4. 실행/빌드 매트릭스

Voyager는 `APP_ENV` 축으로 실행 환경을 구분합니다.

- Debug -> `APP_ENV=dev`
- Release -> `APP_ENV=prod`

`BACKEND_MODE` 기반 source/bundled 분기는 제거되었습니다.

## 5. 보안 원칙 (필수)

- `.env.dev`는 로컬 개발 전용이며, 시크릿이 포함될 수 있으므로 Git 커밋 금지
- `.env.prod`는 프로덕션 템플릿이며, 시크릿은 파일이 아니라 CI/Keychain/런타임 환경 변수로 주입
- 로그에 토큰/키/개인정보/민감한 파일 경로를 남기지 않기

## 6. 트러블슈팅

### 6.1 `.env`가 로드되지 않는 경우

- `VOYAGER_PROJECT_ROOT`가 비어 있으면 자동 추론이 실패할 수 있음
- 번들 실행 환경에서는 `Bundle.main.resourceURL` fallback을 확인

확인 포인트

- `.env.{APP_ENV}` 파일이 project root 또는 resources에 존재하는지
- Debug/Release에 따라 `APP_ENV`가 기대값인지

### 6.2 Gateway/검색 연결 문제

- `PUBLIC_GATEWAY_URL`이 올바른지
- Helper 상태 브로드캐스트(`helper_ready`)가 수신되는지
- XPC 서비스가 정상 기동했는지
