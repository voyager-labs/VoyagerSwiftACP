# 트러블슈팅

Voyager에서 문제가 생겼을 때는 "어느 레이어에서 실패했는지"를 먼저 분리하는 것이 가장 빠릅니다.

- UI/앱 상태 문제: `Voyager` (SwiftUI + TCA)
- 프로세스/포트/인덱싱 문제: `VoyagerHelper`
- API/LLM 변환 문제: Backend (FastAPI)

관련 문서

- ENV/포트/모드: `docs/architecture/environment.md`
- Helper 상세/디버깅: `docs/macos/voyager-helper.md`
- Backend 부트스트랩: `docs/integration/backend-bootstrap.md`
- 검색 동작: `docs/features/search.md`
- 인덱싱 동작: `docs/features/indexing.md`

---

## 0) 빠른 분리 체크(1분)

1) Helper가 살아있는가?

- 메인 앱 로그에서 helper launch 관련 로그가 보이는지 확인

2) Helper가 준비 상태인가?

- Helper 상태 브로드캐스트에서 `helper_ready=true`인지 확인

3) DB에 데이터가 있는가?

- 인덱싱이 끝났는지(`indexing_state.last_sync_at`)

---

## 1) 로그 확인

macOS 통합 로그(권장)

```bash
log stream --predicate 'subsystem == "com.voyager.app"'
```

팁

- "Helper/Backend" 문제는 로그만으로도 원인이 드러나는 경우가 많습니다.
- Sparkle 업데이트 관련 이슈는 업데이트 직전/직후 로그를 같이 확인합니다.

---

## 2) 검색 런타임이 동작하지 않음

### 2.1 개발 환경

체크리스트

- `.env.dev` 파일이 존재하는지 확인
- `VOYAGER_PROJECT_ROOT`가 설정되어 있는지 확인(Helper가 `.env`를 찾는 데 필요할 수 있음)
- `PUBLIC_GATEWAY_URL`, `OPENAI_API_KEY` 등 LLM 관련 키 누락 여부 확인

관련 코드

- `apps/macos/Voyager/Shared/EnvironmentLoader.swift`
- `apps/macos/Voyager/FilterSearchXPC/FilterSearchXPCServiceMain.swift`

### 2.2 배포 환경

체크리스트

- `.env.prod`가 번들 리소스로 복사되었는지
- Helper/XPC 코드 서명 문제로 실행이 막히지 않는지

---

## 3) XPC/Gateway 연결 실패(검색이 안 됨)

현상

- UI에서는 검색이 멈추거나 결과가 비어 있음
- Helper는 떠 있지만 XPC 또는 Gateway 호출이 실패함

원인 패턴

- XPC 서비스가 초기화되지 않았거나 인터럽트됨
- Gateway URL/인증 정보가 잘못되어 변환 요청이 실패함

체크 포인트

- Helper 상태 브로드캐스트 payload에서 `helper_ready`를 확인
- XPC 서비스 로그(`Voyager.FilterSearchXPC`)를 확인
- 방화벽/권한 이슈로 loopback 접근이 막히지 않았는지

관련 코드

- `apps/macos/Voyager/FilterSearchXPC/FilterSearchXPCServiceMain.swift`
- `apps/macos/Voyager/Voyager/04_Features/Composer/Api/SearchClient.swift`

---

## 4) 검색 결과가 계속 0개(또는 이상함)

### 4.1 검색 API의 실패 표현 방식

검색 API는 일부 실패를 HTTP status code가 아니라 응답의 `error` 필드로 표현합니다.

- HTTP 200 + `error != null` 가능
- 현재 Swift 클라이언트는 `error`를 디코딩하지 않아, UI에서 "실패 상세"가 보이지 않을 수 있습니다.

관련 문서

- `docs/features/search.md`

### 4.2 원인 분리 방법

1) LLM 변환 결과 확인

- 동일 요청을 `/api/collection`으로 보내고 `appliedFilters`/`error`를 함께 확인

2) scopes를 배제

- scopes가 너무 좁으면 항상 0개가 나옵니다. scopes를 비우거나 `/`로 넓혀 재확인

3) 레지스트리/조건 불일치

- `propertyKey`가 `ui_hidden`인 경우 서버가 조건 빌드에서 실패할 수 있음
- operator/value shape이 맞지 않으면 변환 결과에서 조건이 제외되거나 `LLM_CONVERSION_FAILED`로 반환될 수 있음

---

## 5) 인덱싱이 진행되지 않음

현상

- 검색이 항상 비어 있음
- Helper 로그에 indexing 관련 로그가 없거나, `running`에서 멈춤

체크 포인트

- 권한(Full Disk Access / Files & Folders)이 제대로 부여됐는지
- `indexing_state`가 어떻게 기록되고 있는지
- stuck recovery 튜닝 키가 과하게 짧게 설정되어 반복 실패하는지

stuck recovery 관련 ENV

- `VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS`
- `VOYAGER_INITIAL_INDEXING_MAX_RETRIES`
- `VOYAGER_INITIAL_INDEXING_MIN_RETRY_INTERVAL_SECONDS`
- `VOYAGER_INITIAL_INDEXING_HEARTBEAT_INTERVAL_SECONDS`

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRequestListener.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Indexing/IndexingRecovery.swift`

DB에서 상태를 직접 보고 싶다면

- DB 위치는 `PUBLIC_SQLITE_FILE_LOCATION` + `PUBLIC_SQLITE_FILE_NAME`로 결정됩니다.
- `indexing_state`는 key/value 테이블입니다.

---

## 6) Xcode 버전 불일치

- 레포 루트의 `.xcode-version` 확인
- `scripts/xcodes.sh` 실행

---

## 7) 업데이트(Sparkle) 관련 이슈

현상

- 업데이트 확인이 전혀 동작하지 않음
- 업데이트 후 relaunch가 지연됨

체크 포인트

- Sparkle 설정(FeedURL)이 Info.plist에 존재하는지
  - `apps/macos/Voyager/Voyager/01_App/Config/Info.plist`
- relaunch 직전 Helper 종료가 지연되고 있을 수 있음(UpdaterClient의 fail-safe 로그 확인)

관련 문서

- `docs/features/update.md`
