# 인덱싱 기능

인덱싱(Indexing)은 로컬 파일 시스템의 메타데이터를 수집해 Helper 내부 SQLite(DB)에 저장하고, 이후 변경 사항을 지속적으로 반영하는 기능입니다.

Voyager에서 인덱싱은 macOS 앱(UI) 프로세스가 아닌 **VoyagerHelper 프로세스**가 수행합니다.

## 큰 그림

인덱싱은 크게 두 단계로 구성됩니다.

1) 초기 인덱싱(initial indexing)

- 최초 1회(또는 복구 시 재시도)
- 홈 디렉터리를 범위로 대량 스캔

2) 증분 인덱싱(incremental indexing)

- 초기 인덱싱 완료 후 시작
- FSEvents를 통해 파일 변경 이벤트를 감시하고 DB를 갱신

## 트리거(시작): macOS 앱 → Helper

인덱싱 시작은 macOS 앱이 Helper에게 “요청”을 보내는 방식으로 트리거됩니다.

- 앱: `IndexingClient.start()` 호출
- 전달: `DistributedNotificationCenter`로 `.voyagerIndexingRequest` 브로드캐스트
- Helper: `IndexingRequestListener.startObservingRequests()`가 해당 알림을 구독하고 요청을 처리

관련 코드

- `apps/macos/Voyager/Shared/Notifications/IndexingNotifications.swift`
- `apps/macos/Voyager/Voyager/04_Features/Indexing/Api/IndexingClient.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRequestListener.swift`

## 초기 인덱싱

### 실행 조건(스킵 규칙)

초기 인덱싱은 홈 디렉터리를 대상으로 수행되지만, 항상 실행되지는 않습니다.

- `indexing_state` 테이블의 `last_sync_at`이 존재하며 값이 `"null"`이 아니면 초기 인덱싱은 스킵됩니다.
- 즉, 초기 인덱싱의 “완료/재실행 방지”는 `initial_indexing_status`만이 아니라 `last_sync_at`로도 보강됩니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/InitialIndexingRunner.swift`

### 상태 머신(요약)

Helper는 `indexing_state` 테이블에 초기 인덱싱 상태를 기록합니다.

- `initial_indexing_status`: `pending` → `running` → `completed`
- `initial_indexing_requested_at`, `initial_indexing_started_at`, `initial_indexing_completed_at`: 타임스탬프
- `initial_indexing_last_heartbeat`: 장시간 실행 중 “멈춤(stuck)” 탐지에 사용
- `initial_indexing_retry_count`, `initial_indexing_last_retry_at`, `initial_indexing_reset_reason`: 복구(recovery) 기록

요청 처리 시 동작

- 이미 `running`이면 중복 실행을 막고, 필요 시 “stuck recovery”를 시도합니다.
- 이미 `completed`이면 요청을 무시합니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRequestListener.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRecovery.swift`

### 스캔 방식(현재 구현)

`InitialIndexingRunner`는 Spotlight(CoreServices)의 `MDQuery`를 사용해 홈 디렉터리를 스캔합니다.

- 쿼리: `kMDItemContentTypeTree == "public.item"`
- 스코프: `FileManager.default.homeDirectoryForCurrentUser`
- 결과의 `kMDItemPath`를 읽어 경로를 얻고, DB에 이미 존재하는 경로는 건너뜁니다.
- 삽입은 배치로 수행되며, SQLite의 `PRAGMA max_variable_number`를 고려해 “경로 조회(path IN (...))” 배치 크기를 조정합니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/InitialIndexingRunner.swift`

### 초기 인덱싱 중 성능 튜닝(PRAGMA)

대량 삽입 동안에는 DB 성능을 위해 PRAGMA를 일시적으로 변경하고, 작업이 끝나면 복구합니다.

- 적용 예시: `journal_mode=WAL`, `synchronous=NORMAL`, `temp_store=MEMORY`, `cache_size=-16384`, `mmap_size=134217728`
- 복구: 작업 전 스냅샷을 저장한 뒤 원래 값으로 되돌림

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingDatabasePragmas.swift`

### 하트비트(heartbeat)와 stuck recovery

초기 인덱싱은 홈 디렉터리 전체를 스캔하므로 장시간 실행될 수 있습니다.
Helper는 `initial_indexing_last_heartbeat`를 갱신하며, “오랜 시간 변화가 없는 running 상태”를 stuck으로 판단해 복구를 시도합니다.

동작 개요

- running 상태에서 요청/prepare가 들어오면 `recoverIfStuckIfNeeded(...)`를 수행
- 기준 시각(reference)은 `initial_indexing_last_heartbeat` 우선, 없으면 `initial_indexing_started_at`
- 기준 시각으로부터 `VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS`가 지나면 recovery 트리거
- recovery 트리거 시 `initial_indexing_status`를 `pending`으로 리셋하고 `.recovery` 트리거로 재시작
- 재시도 횟수/간격은 아래 환경 변수로 제한

조정 가능한 환경 변수(Helper 프로세스 env)

- `VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS` (default: 21600 = 6h)
- `VOYAGER_INITIAL_INDEXING_MAX_RETRIES` (default: 3)
- `VOYAGER_INITIAL_INDEXING_MIN_RETRY_INTERVAL_SECONDS` (default: 600 = 10m)
- `VOYAGER_INITIAL_INDEXING_HEARTBEAT_INTERVAL_SECONDS` (default: 300 = 5m)

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRecovery.swift`

### 초기 인덱싱 완료 후

초기 인덱싱이 성공하면

- `indexing_state.last_sync_at`를 ISO 8601 timestamp로 갱신
- 곧바로 `IncrementalIndexingValidator.startIfReady(...)`를 호출해 증분 인덱싱을 시작할지 판단

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRequestListener.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/InitialIndexingRunner.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingValidator.swift`

## 증분 인덱싱

증분 인덱싱은 초기 인덱싱 완료 이후, 파일 변경 이벤트를 감지해 DB를 갱신합니다.

### 시작 게이트(ready check)

`IncrementalIndexingValidator.startIfReady()`는 `indexing_state`에서 다음을 확인합니다.

- `watched_paths`가 존재해야 함(값이 비어 있어도 키 존재 자체가 필요)
- `last_sync_at`가 존재하며 값이 `"null"`이 아니어야 함

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingValidator.swift`

### 감시(FSEvents) 아키텍처

`IncrementalIndexingWatcher`는 FSEvents 스트림을 “전용 스레드 + RunLoop”에서 돌리고, 이벤트 처리는 별도의 직렬 큐 및 Task 체인으로 처리합니다.

핵심 포인트

- FSEvents 콜백에서 path/flags/ids를 즉시 복사한 뒤 watcher로 전달
- watcher는 `eventQueue`(serial)에서 이벤트를 정규화/집계
- DB 반영은 `processingTask`를 체인으로 연결해 직렬화(이전 작업이 끝난 뒤 다음 작업 실행)

### 감시 경로(watched_paths)

- `indexing_state.watched_paths`는 JSON 문자열(`[String]`)로 저장됩니다.
- JSON 디코딩이 실패하거나 값이 비어 있으면 홈 디렉터리를 기본 감시 경로로 사용합니다.
- 감시 시작 시, watcher는 표준화된 경로(`standardizedFileURL.path`)로 정규화합니다.

### 재시작/복구 기준(last_fsevent_id)

- `indexing_state.last_fsevent_id`를 읽어 FSEvents 시작 지점(`sinceEventId`)을 결정합니다.
- 값이 없으면 `kFSEventStreamEventIdSinceNow`로 시작합니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IncrementalIndexingWatcher.swift`

## 데이터 저장(Helper SQLite)

저장소는 Helper 내부의 GRDB 기반 SQLite입니다.

- `DatabaseManager`가 read/write 풀과 트랜잭션/비트랜잭션 write API를 제공합니다.
- 앱 실행 시 `DatabaseMigrations`로 마이그레이션을 적용해 스키마를 맞춥니다.

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseMigrations.swift`

## QA 체크리스트(재현 가능한 단계)

- 트리거 전달
  - 앱에서 `IndexingClient.start()` 호출 → Helper 로그에 "Indexing request listener started" 및 요청 수신 로그가 찍히는지 확인
- 초기 인덱싱 상태 전이
  - 첫 요청에서 `initial_indexing_status`가 `pending -> running -> completed`로 전이되는지 확인
  - 완료 후 같은 요청을 보내면 "already completed; request ignored"로 무시되는지 확인
- last_sync_at 스킵
  - `indexing_state.last_sync_at`이 세팅된 상태에서 초기 인덱싱이 스킵되는지 확인("Home indexing skipped")
- stuck recovery
  - (테스트) `initial_indexing_status=running` + `initial_indexing_last_heartbeat`를 과거로 세팅
  - 요청을 다시 보내면 recovery가 트리거되고 status가 `pending`으로 리셋된 뒤 재시작되는지 확인
- 증분 인덱싱 게이트
  - `watched_paths` 키가 존재 + `last_sync_at`이 `null`이 아닌 경우에만 watcher가 시작되는지 확인
- watched_paths 디코딩 실패 fallback
  - `watched_paths`를 깨진 JSON으로 저장 → watcher가 홈 디렉터리로 fallback 하는지 확인

## 트러블슈팅

### 초기 인덱싱이 반복 실행됨

- `indexing_state.last_sync_at`이 갱신되는지 확인합니다.
- stuck recovery가 과하게 트리거되는 경우, `VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS` 및 `VOYAGER_INITIAL_INDEXING_HEARTBEAT_INTERVAL_SECONDS` 설정을 점검합니다.

### 초기 인덱싱이 running에서 멈춘 것처럼 보임

- `initial_indexing_last_heartbeat`가 주기적으로 갱신되는지 확인합니다.
- 장시간 갱신이 없다면, 다음 요청에서 stuck recovery가 트리거될 수 있습니다.

### 증분 인덱싱이 시작되지 않음

- `IncrementalIndexingValidator`의 게이트 조건을 점검합니다.
  - `watched_paths` 키 존재 여부
  - `last_sync_at` 값이 `"null"`인지 여부
- `watched_paths`의 JSON 디코딩 실패로 홈 디렉터리로 fallback 되고 있을 수 있으니, 값의 포맷을 확인합니다.
