# 환경 설정 (ENV)

Voyager는 macOS 앱/Helper/Backend가 같은 키 체계를 공유하도록 설계되어 있습니다.
환경 값은 기본적으로 **`.env` 파일 + 런타임 환경 변수**의 조합으로 구성됩니다.

## 1. 로딩 전략

### 1.1 macOS (Voyager / VoyagerHelper)

macOS 쪽은 `EnvironmentLoader.loadEnvFiles()`를 통해 환경 파일을 로드합니다.

- `APP_ENV`: `dev` 또는 `prod`
- `BACKEND_MODE`: `source` 또는 `bundled`

로드 순서

1) `.env.{BACKEND_MODE}`
2) `.env.{APP_ENV}`

source 모드에서의 base 디렉터리

- `VOYAGER_PROJECT_ROOT`가 반드시 필요합니다.
  - 이 값이 없으면 `.env.*` 파일을 찾지 못해 로딩이 실패할 수 있습니다.

bundled 모드에서의 base 디렉터리

- 앱 번들의 `Bundle.main.resourceURL`을 base로 사용합니다.

관련 코드

- `apps/macos/Voyager/Shared/EnvironmentLoader.swift`

### 1.2 Backend (FastAPI)

백엔드는 `app.config.load_env()`에서 `.env` 파일을 로드합니다.

- 로딩 우선순위는 **프로세스 환경 변수 > `.env.{BACKEND_MODE}` > `.env.{APP_ENV}`** 입니다.
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

### 2.3 Backend 연결

- `PUBLIC_BACKEND_HOST`
- `PUBLIC_BACKEND_PORT`
  - `0`이면 Helper가 동적 포트를 예약하고 실제 포트를 선택합니다.
- `PUBLIC_BACKEND_PROCESS_NAME`
- `PUBLIC_BACKEND_URL`
  - 고정 `.env` 값이 아니라, Helper 상태 브로드캐스트로 런타임에 설정될 수 있습니다.

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Api/HelperStateClient.swift`
- `apps/macos/Voyager/Voyager/04_Features/Composer/Api/SearchClient.swift`

### 2.4 SQLite

- `PUBLIC_SQLITE_PROTOCOL`
- `PUBLIC_SQLITE_ECHO`
- `PUBLIC_SQLITE_CHECK_SAME_THREAD`
- `PUBLIC_SQLITE_FILE_LOCATION`
- `PUBLIC_SQLITE_FILE_NAME`

관련 코드

- `apps/backend/src/app/config.py`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`

### 2.5 Observability (Sentry)

- `PUBLIC_SENTRY_DSN` (없으면 Sentry 비활성)
- `PUBLIC_SENTRY_TRACES_SAMPLE_RATE`

관련 코드

- `apps/macos/Voyager/Shared/Logging/SentryBootstrap.swift`

### 2.6 Indexing 튜닝

초기 인덱싱 recovery 동작은 다음 키로 튜닝할 수 있습니다.

- `VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS`
- `VOYAGER_INITIAL_INDEXING_MAX_RETRIES`
- `VOYAGER_INITIAL_INDEXING_MIN_RETRY_INTERVAL_SECONDS`
- `VOYAGER_INITIAL_INDEXING_HEARTBEAT_INTERVAL_SECONDS`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRecovery.swift`

## 3. 파일별 역할

레포 루트에 기본 템플릿이 존재합니다.

- `.env.source`: source 모드에서 주로 쓰는 PUBLIC 백엔드/DB 설정 (시크릿 금지)
- `.env.bundled`: bundled 모드에서 주로 쓰는 PUBLIC 백엔드/DB 설정 (시크릿 금지)
- `.env.dev` (Git ignored): 로컬 개발 환경 (시크릿 포함 가능)
- `.env.prod` (Git tracked): 프로덕션 템플릿 (시크릿 금지; CI/런타임에서 주입)
- `.env.example`: 키 목록 참고용

---

## 4. 실행/빌드 매트릭스 (Debug/Release x Dev/Prod)

Voyager는 두 축으로 실행 환경이 결정됩니다.

- APP_ENV (dev/prod): 빌드 설정 기반 (Debug -> dev, Release -> prod)
- BACKEND_MODE (source/bundled): 스킴 기반 (Dev -> source, Prod -> bundled)

| 스킴 | 빌드 설정 | APP_ENV | BACKEND_MODE | 백엔드 실행 방식 |
|---|---|---|---|---|
| `Voyager-Dev` | Debug | `dev` | `source` | 로컬 `uv` (`uv run dev`) |
| `Voyager-Dev` | Release | `prod` | `source` | 로컬 `uv` (운영 설정 템플릿 기반) |
| `Voyager-Prod` | Debug | `dev` | `bundled` | 번들 바이너리 (`server/server.bin`) |
| `Voyager-Prod` | Release | `prod` | `bundled` | 번들 바이너리 (`server/server.bin`) |

주의

- 위 표는 "축"을 설명하기 위한 것입니다. 실제로는 팀에서 사용하는 스킴/빌드 조합을 표준화해서 운영하는 것이 중요합니다.
- 로컬 개발에서는 일반적으로 `Voyager-Dev` + Debug가 가장 빠른 반복을 제공합니다.

---

## 5. 보안 원칙 (필수)

- `.env.dev`는 로컬 개발 전용이며, 시크릿이 포함될 수 있으므로 Git 커밋 금지
- `.env.prod`는 프로덕션 템플릿이며, 시크릿은 파일이 아니라 CI/Keychain/런타임 환경변수로 주입
- 로그에 토큰/키/개인정보/민감한 파일 경로를 남기지 않기

---

## 6. 트러블슈팅

### 6.1 `.env`가 로드되지 않는 경우

- `BACKEND_MODE=source`일 때 `VOYAGER_PROJECT_ROOT`가 없으면 `.env.*`를 찾지 못할 수 있습니다.
- `BACKEND_MODE=bundled`일 때는 번들 리소스(앱 번들 Resources) 기준으로 탐색합니다.

확인 포인트

- `.env.{BACKEND_MODE}` / `.env.{APP_ENV}` 파일이 기대한 base 디렉터리에 존재하는지
- 스킴 환경변수에 `BACKEND_MODE`가 주입되어 있는지
- Debug/Release에 따라 `APP_ENV`가 기대값으로 들어오는지

### 6.2 포트 충돌 / 백엔드 접속 불가

- `PUBLIC_BACKEND_PORT=0`이면 Helper가 동적 포트를 예약합니다.
- 충돌이 의심되면 "Helper가 실제로 예약한 포트"와 "클라이언트가 호출하는 URL"이 일치하는지부터 확인합니다.

확인 포인트

- `PUBLIC_BACKEND_URL`이 런타임에 Helper 상태 브로드캐스트로 덮어써졌는지
- 방화벽/권한 이슈로 로컬 loopback 접근이 막히지 않았는지

### 6.3 `uv`를 찾지 못하는 경우 (source 모드)

- `BACKEND_MODE=source`에서 Helper는 `uv`를 실행합니다. 개발 머신 PATH에 `uv`가 없으면 실행에 실패합니다.

확인 포인트

- 터미널에서 `uv --version`이 동작하는지
- Xcode 실행 환경(PATH)이 셸과 달라질 수 있으므로, 필요하면 문서화된 방식으로 PATH를 맞춥니다.
