# VoyagerHelper 상세 문서

VoyagerHelper는 macOS 앱(Voyager)과 별도의 프로세스로 실행되는 **Helper 앱**입니다.
역할은 크게 2가지입니다.

1) 백엔드 프로세스(Python FastAPI)를 올바른 모드로 실행/감시/재시작
2) 파일 메타데이터 인덱싱(초기/증분)을 수행하고 SQLite에 저장

관련 코드 루트

- Helper 엔트리: `apps/macos/Voyager/VoyagerHelper/VoyagerHelperApp.swift`
- Backend 런처: `apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift`
- Backend 재시작 루프: `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperLifecycle.swift`
- 상태 브로드캐스트: `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- 인덱싱: `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/*`
- DB/마이그레이션: `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/*`

## 1. 실행/통합 개요

### 1.1 메인 앱이 Helper를 실행하는 방식

메인 앱은 `NSWorkspace`로 Helper 앱 번들을 실행합니다.

- Helper 찾기: 메인 앱 번들 내 `Contents/Helpers/VoyagerHelper.app` 또는 형제 경로
- 실행: `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)`
- 종료: SIGTERM → (대기) → forceTerminate → SIGKILL 순서

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Api/HelperAppClient.swift`

### 1.2 Helper가 메인 앱과 동기화하는 방식

Helper는 `DistributedNotificationCenter`를 사용해 상태를 브로드캐스트합니다.

- 요청 알림: `Notification.Name.voyagerHelperStateRequest`
- 응답/갱신 알림: `Notification.Name.voyagerHelperStateDidUpdate`

payload 스키마는 `schema_version=2`로 관리됩니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- `apps/macos/Voyager/Shared/Notifications/HelperStateNotifications.swift`

## 2. Helper 프로세스 부트 순서

`VoyagerHelperApp.main()`의 흐름은 다음과 같습니다.

1) 로깅 부트스트랩
2) 환경 로딩(`Environment()` 초기화 과정에서 `.env` 로딩 시도)
3) DB 초기화 + 마이그레이션
4) 상태 브로드캐스터 준비(요청 옵저빙 시작 + 현재 상태 푸시)
5) 인덱싱 요청 리스너 준비/시작
6) 초기 인덱싱 완료 상태면 증분 인덱싱 가드 오픈
7) 백엔드 재시작 루프 시작

관련 코드

- `apps/macos/Voyager/VoyagerHelper/VoyagerHelperApp.swift`

## 3. 환경/설정 로딩

Helper는 SwiftDotenv를 사용하며, 부팅 과정에서 `.env` 파일을 로드합니다.

- 로드 파일: `.env.{BACKEND_MODE}` + `.env.{APP_ENV}`
- source 모드에서 `.env` 파일을 찾기 위해 `VOYAGER_PROJECT_ROOT`가 필요합니다.

세부 로딩 규칙/키 목록은 `docs/architecture/environment.md`에 정리합니다.

### 3.1 BACKEND_MODE에 따른 백엔드 디렉터리

- `BACKEND_MODE=source`
  - 프로젝트 루트 기준 `apps/backend`를 백엔드 디렉터리로 사용
  - `apps/backend/pyproject.toml` 또는 `apps/backend/uv.lock`가 존재해야 함
- `BACKEND_MODE=bundled`
  - Helper 번들 리소스의 `server/` 디렉터리를 백엔드 디렉터리로 사용

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Environment.swift`

### 3.2 Helper/Backend 연동 핵심 환경 변수

메인 앱/Helper/Backend가 공유하는 키들입니다.

- `PUBLIC_BACKEND_HOST`
- `PUBLIC_BACKEND_PORT`
  - 초기값은 `0`을 권장하며, 실행 시 Helper가 동적 포트를 예약하여 실제 포트로 덮어씁니다.
- `PUBLIC_BACKEND_PROCESS_NAME`
  - bundled 모드에서 실행할 바이너리 파일명
- `PUBLIC_BACKEND_URL`
  - 메인 앱이 Helper 상태를 수신한 뒤 런타임에 설정될 수 있습니다.
- `APP_ENV`
  - Python이 `.env.{app_env}` 파일을 고르기 위한 키 (예: dev/prod)
- `BACKEND_MODE`
  - source/bundled

추가로 Helper DB 설정은 `.env` 또는 프로세스 환경에서 읽습니다.

- `PUBLIC_SQLITE_FILE_LOCATION`
- `PUBLIC_SQLITE_FILE_NAME`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`
- `docs/architecture/environment.md`

## 4. 백엔드 실행 (ProcessRunner)

Helper는 백엔드 프로세스를 **단일 인스턴스**로 실행하고, 준비 상태를 검증합니다.

### 4.1 포트 예약 및 준비 검증

- 동적 포트 예약: `PortReservationService.reserve()`
  - OS에 bind(0) 후 getsockname으로 실제 포트를 확보
- 준비 확인: `verifyListening(host:port:isRunning:shouldStop:)`
  - 최대 N회 재시도하며 TCP connect 가능 여부로 준비 판단

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/PortReservationService.swift`

### 4.2 source vs bundled 실행 커맨드

- source 모드
  - 실행 파일: `/usr/bin/env`
  - args: `uv run <APP_ENV>` (예: `uv run dev`)
  - PATH에 homebrew 경로를 prefix로 주입 (uv 실행 보장)
- bundled 모드
  - 실행 파일: `{Bundle.resources}/server/{PUBLIC_BACKEND_PROCESS_NAME}`
  - args 없음

중요: Helper는 자신의 프로세스 환경을 백엔드에 그대로 전달하고,
`PUBLIC_BACKEND_PORT`는 예약한 포트로 덮어씁니다. (source 모드에서는 `uv` 실행을 위해 `PATH`를 보정)
Python 백엔드는 `load_config()`에서 `.env.{BACKEND_MODE}` + `.env.{APP_ENV}`를 `override=False`로 로드하므로
별도의 dotenv "전파"가 없어도 동작합니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift`
- `apps/backend/src/app/config.py`

### 4.3 Helper 상태 브로드캐스트

백엔드 준비가 완료되면 Helper는 다음을 브로드캐스트합니다.

- `helper_ready=true`
- `backend.ready=true`
- `backend.pid`, `backend.uptime_seconds`
- `backend.endpoint.{host,port,url}`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- `apps/macos/Voyager/Shared/Notifications/HelperStateNotifications.swift`

## 5. 백엔드 재시작 정책 (HelperLifecycle)

Helper는 백엔드 종료 이벤트를 감지하고, 지수 백오프로 재시도합니다.

- backoff: `[1, 2, 4, 8, 16]` 초
- 안정 기동 기준: `wasReady && uptime >= 2s`
  - 안정 기동이면 attempt 카운터를 0으로 리셋
- 재시도 초과 시: helper 프로세스 종료
- SIGINT/SIGTERM/SIGQUIT/SIGHUP를 핸들링하여 graceful stop

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperLifecycle.swift`

## 6. 인덱싱

### 6.1 인덱싱 요청 트리거

Helper는 `DistributedNotificationCenter`에서 인덱싱 요청을 구독합니다.

- 요청 알림: `Notification.Name.voyagerIndexingRequest`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRequestListener.swift`
- `apps/macos/Voyager/Shared/Notifications/IndexingNotifications.swift`

### 6.2 초기 인덱싱 (InitialIndexingRunner)

- 홈 디렉터리 스코프로 Spotlight(`MDQuery`)를 사용해 파일을 탐색
- 배치로 DB에 insert/upsert
- 완료 시 `indexing_state.last_sync_at` 업데이트

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/InitialIndexingRunner.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/Repositories/EntryRepository.swift`

### 6.3 stuck 감지 및 복구 (IndexingRecovery)

초기 인덱싱이 `running` 상태에서 장시간 진행되지 않으면 recovery가 동작할 수 있습니다.

- 참조 시간: `initial_indexing_last_heartbeat` 우선, 없으면 `initial_indexing_started_at`
- timeout 기본값: `6h`
- 최대 재시도: `3`
- 최소 재시도 간격: `10m`
- heartbeat 기본 주기: `5m`

환경 변수로 튜닝 가능

- `VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS`
- `VOYAGER_INITIAL_INDEXING_MAX_RETRIES`
- `VOYAGER_INITIAL_INDEXING_MIN_RETRY_INTERVAL_SECONDS`
- `VOYAGER_INITIAL_INDEXING_HEARTBEAT_INTERVAL_SECONDS`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRecovery.swift`

### 6.4 증분 인덱싱 (FSEvents)

초기 인덱싱이 완료되면, Helper는 FSEvents로 변경을 추적합니다.

- `indexing_state.watched_paths`에 감시 경로 JSON 저장
  - 값이 없으면 기본값은 `$HOME`
- `indexing_state.last_fsevent_id`에 마지막 처리 이벤트 ID 저장
- 드롭/오버플로 발생 시 rescan 경로를 계산하여 부분 재스캔

처리 흐름

1) FSEvents 콜백에서 paths/flags/ids를 즉시 복사
2) Planner가 watched paths 기준으로 정규화 + upsert/delete 결정
3) Executor가 변경을 DB에 적용 + rescan(필요 시) + last_fsevent_id 저장

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingWatcher.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingEventPlanner.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingEventExecutor.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingValidator.swift`

## 7. DB 스키마/마이그레이션

Helper는 GRDB의 `DatabasePool`을 사용합니다.

### 7.1 DB 파일 경로

`DatabaseManager`는 다음 환경 변수에서 DB 위치를 구성합니다.

- `PUBLIC_SQLITE_FILE_LOCATION`
  - 상대 경로인 경우 CWD 기준으로 해석
  - `~` 확장 지원
- `PUBLIC_SQLITE_FILE_NAME`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`

### 7.2 테이블

- `entries`
  - 파일 메타데이터의 정규화 컬럼 + `original_metadata` JSON
  - 유니크 키: `(volume_identifier, file_resource_identifier)`
- `indexing_state`
  - 인덱싱 상태/타임스탬프/재시도 정보 등 key-value 저장

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/Schema/EntriesSchema.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/Schema/IndexingStateSchema.swift`

### 7.3 마이그레이션

- 마이그레이션은 번들 리소스 `Migrations/` 디렉터리의 `*.sql`로 관리
- 파일명(확장자 제외)이 migration id
- 실행 순서: 파일명 오름차순
- 기존 DB에 unknown migration이 있거나 history prefix가 다르면 실패

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseMigrations.swift`

## 8. 메타데이터 인코딩

Helper는 Spotlight 메타데이터(`MDItem`)를 JSON 문자열로 인코딩하여 `entries.original_metadata`에 저장합니다.

- 특정 키는 xattr에서 보강
  - `_kMDItemUserTags` → `com.apple.metadata:_kMDItemUserTags`
  - `kMDItemFinderComment` → `com.apple.metadata:kMDItemFinderComment` fallback

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/MetadataJSONEncoder.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/XattrMetadataReader.swift`

## 9. 운영/디버깅 체크리스트

### 9.1 Helper가 실행되었는지

- 메인 앱 로그에서 `helper_launch_*` 확인
- `HelperAppClient.isRunning()`로 확인

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Api/HelperAppClient.swift`

### 9.2 백엔드가 준비 상태인지

- Helper 상태 요청 알림을 보내고 응답 payload에서 `backend.ready=true` 확인
- 포트 연결 실패 시 `PortReservationService.verifyListening` 로그/상태 확인

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/PortReservationService.swift`

### 9.3 인덱싱 상태 확인

- `indexing_state`의 키들 확인
  - `last_sync_at`
  - `watched_paths`
  - `last_fsevent_id`
  - `initial_indexing_*`

### 9.4 번들 모드 문제

- `BACKEND_MODE=bundled`인데 `Resources/server/`가 없으면 `Environment.backendDirectory()`에서 실패
- `PUBLIC_BACKEND_PROCESS_NAME`이 비어 있거나 바이너리 파일이 없으면 `ProcessRunner`에서 실패

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Environment.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift`
- `scripts/build/build-backend-binary.sh`
