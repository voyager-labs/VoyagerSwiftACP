# VoyagerHelper 상세 문서

VoyagerHelper는 macOS 앱(Voyager)과 별도의 프로세스로 실행되는 Helper 앱입니다.

현재 역할은 아래 두 축으로 정리됩니다.

1) 인덱싱/로컬 DB 관리(GRDB)
2) 검색 런타임 보조(XPC 서비스와 상태 브로드캐스트)

로컬 FastAPI 백엔드 프로세스 실행/감시/재시작 기능은 제거되었습니다.

관련 코드 루트

- Helper 엔트리: `apps/macos/Voyager/VoyagerHelper/VoyagerHelperApp.swift`
- 상태 브로드캐스트: `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- 인덱싱: `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/*`
- DB/마이그레이션: `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/*`
- XPC 엔트리: `apps/macos/Voyager/FilterSearchXPC/FilterSearchXPCServiceMain.swift`

## 1. 실행/통합 개요

### 1.1 메인 앱이 Helper를 실행하는 방식

메인 앱은 `NSWorkspace`로 Helper 앱 번들을 실행합니다.

- Helper 찾기: 메인 앱 번들 내 `Contents/Helpers/VoyagerHelper.app` 또는 형제 경로
- 실행: `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)`
- 종료: SIGTERM -> (대기) -> forceTerminate -> SIGKILL 순서

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Api/HelperAppClient.swift`

### 1.2 Helper가 메인 앱과 동기화하는 방식

Helper는 `DistributedNotificationCenter`를 사용해 상태를 브로드캐스트합니다.

- 요청 알림: `Notification.Name.voyagerHelperStateRequest`
- 응답/갱신 알림: `Notification.Name.voyagerHelperStateDidUpdate`

payload 스키마는 `schema_version=3`으로 관리됩니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- `apps/macos/Voyager/Shared/Notifications/HelperStateNotifications.swift`

## 2. Helper 프로세스 부트 순서

`VoyagerHelperApp.main()`의 흐름은 다음과 같습니다.

1) 로깅 부트스트랩
2) 환경 로딩(`EnvironmentLoader.loadEnvFiles()`)
3) DB 초기화 + 마이그레이션
4) 상태 브로드캐스터 준비(요청 옵저빙 시작 + 현재 상태 푸시)
5) 인덱싱 요청 리스너 준비/시작
6) 초기 인덱싱 완료 상태면 증분 인덱싱 가드 오픈

관련 코드

- `apps/macos/Voyager/VoyagerHelper/VoyagerHelperApp.swift`

## 3. 환경/설정 로딩

Helper는 SwiftDotenv를 사용하며, 부팅 과정에서 `.env.{APP_ENV}` 파일을 로드합니다.

- project root 우선(`VOYAGER_PROJECT_ROOT` 사용 가능)
- 없으면 bundle resources fallback

세부 로딩 규칙/키 목록은 `docs/architecture/environment.md`에 정리합니다.

관련 코드

- `apps/macos/Voyager/Shared/EnvironmentLoader.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`

## 4. 상태 브로드캐스트

Helper는 준비 상태를 앱에 브로드캐스트합니다.

- `helper_ready`
- `helper_bundle_version`
- `generated_at`

`backend` 블록(endpoint/port/url) 전달은 제거되었습니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- `apps/macos/Voyager/Voyager/01_App/Api/HelperStateClient.swift`

## 5. 인덱싱

### 5.1 인덱싱 요청 트리거

Helper는 `DistributedNotificationCenter`에서 인덱싱 요청을 구독합니다.

- 요청 알림: `Notification.Name.voyagerIndexingRequest`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRequestListener.swift`
- `apps/macos/Voyager/Shared/Notifications/IndexingNotifications.swift`

### 5.2 초기 인덱싱 (InitialIndexingRunner)

- 홈 디렉터리 스코프로 Spotlight(`MDQuery`)를 사용해 파일 탐색
- 배치로 DB insert/upsert
- 완료 시 `indexing_state.last_sync_at` 업데이트

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/InitialIndexingRunner.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/Repositories/EntryRepository.swift`

### 5.3 stuck 감지 및 복구 (IndexingRecovery)

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

### 5.4 증분 인덱싱 (FSEvents)

초기 인덱싱이 완료되면 Helper는 FSEvents로 변경을 추적합니다.

- `indexing_state.watched_paths`에 감시 경로 JSON 저장
- `indexing_state.last_fsevent_id`에 마지막 처리 이벤트 ID 저장
- 드롭/오버플로 발생 시 rescan 경로를 계산하여 부분 재스캔

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingWatcher.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingEventPlanner.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingEventExecutor.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingValidator.swift`

## 6. DB 스키마/마이그레이션

Helper는 GRDB의 `DatabasePool`을 사용합니다.

### 6.1 DB 파일 경로

`DatabaseManager`는 다음 환경 변수에서 DB 위치를 구성합니다.

- `PUBLIC_SQLITE_FILE_LOCATION`
- `PUBLIC_SQLITE_FILE_NAME`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`

### 6.2 테이블

- `entries`
- `indexing_state`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/Schema/EntriesSchema.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/Schema/IndexingStateSchema.swift`

### 6.3 마이그레이션

- 번들 리소스 `Migrations/`의 `*.sql` 관리
- 파일명(확장자 제외)이 migration id
- 실행 순서: 파일명 오름차순

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseMigrations.swift`

## 7. 운영/디버깅 체크리스트

### 7.1 Helper가 실행되었는지

- 메인 앱 로그에서 `helper_launch_*` 확인
- `HelperAppClient.isRunning()`으로 확인

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Api/HelperAppClient.swift`

### 7.2 Helper 상태가 준비인지

- Helper 상태 요청 알림을 보내고 응답 payload에서 `helper_ready=true` 확인

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`
- `apps/macos/Voyager/Voyager/01_App/Api/HelperStateClient.swift`

### 7.3 인덱싱 상태 확인

- `indexing_state.last_sync_at`
- `indexing_state.watched_paths`
- `indexing_state.last_fsevent_id`
- `initial_indexing_*`
