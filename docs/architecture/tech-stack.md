# 기술 스택

이 문서는 Voyager 모노레포에서 사용하는 기술을 단순 나열이 아니라, 각 기술의 역할 / 선정 이유 / 주의점 / 버전 정책까지 포함해 정리합니다.

관련 문서

- `docs/architecture/overview.md`
- `docs/architecture/source-tree.md`
- `docs/architecture/macos-app.md`
- `docs/architecture/environment.md`
- `docs/architecture/coding-standards.md`

---

## 버전 정책 (핀 vs 비핀)

Voyager는 가능한 범위에서 버전을 고정해 재현 가능한 개발/빌드를 목표로 합니다.

- Xcode: 레포 루트의 `.xcode-version`으로 고정
- Python: `apps/backend/.python-version`으로 고정
- Swift 의존성(SPM): `apps/macos/Voyager/Voyager.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`에 버전/리비전이 고정
- Python 의존성(uv): 선언은 `apps/backend/pyproject.toml`, 실제 고정 버전은 `apps/backend/uv.lock`에 기록

문서에서 버전 표기 기준

- 설정 파일에 정확한 버전이 명시되어 있으면 그 값을 표기합니다.
- 선언이 `>=` 형태라도 `uv.lock`가 존재하면, 실제 설치/빌드 기준 버전은 lock 기준으로 고정된 것으로 간주합니다.
- 어디에도 근거가 없으면 "핀되지 않음"이라고 명시합니다.

현재 레포 기준(참고)

- Xcode: `26.1` (`.xcode-version`)
- Python: `3.13.7` (`apps/backend/.python-version`)

---

## macOS 앱 (Voyager 타깃)

범위

- UI 및 상태 관리: `apps/macos/Voyager/Voyager/`
- 앱 진입점/라이프사이클: `apps/macos/Voyager/Voyager/01_App/`

### SwiftUI

- 역할: macOS UI(뷰 계층) 구현, 상태 변화에 따른 선언적 렌더링
- 선정 이유: AppKit 대비 빠른 UI 반복, Swift Concurrency/TCA와 결합이 자연스러움
- 주의점
    - 복잡한 AppKit 상호작용은 브리징이 필요할 수 있음(예: NSViewRepresentable)
    - 성능 이슈는 뷰 계층 구조/State 폭발로 이어지기 쉬워, 상태 분리와 렌더링 범위 최소화가 중요
- 버전: Xcode/SDK에 종속(별도 핀 없음)

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Ui/VoyagerApp.swift`

### TCA (The Composable Architecture)

- 역할: 단방향 데이터 흐름(State/Action/Reducer), Effect 처리, 테스트 가능한 설계
- 선정 이유
    - 상태/이펙트/의존성 주입을 한 패턴으로 통일
    - 기능 단위(Feature)로 분해하기 쉬워, FSD 스타일 구조와 궁합이 좋음
- 주의점
    - Feature가 커지면 Reducer/Action이 비대해지기 쉬우므로, `docs/architecture/macos-app.md`의 분해/오케스트레이터 패턴을 우선
    - async Effect는 취소/경합 관리가 설계 품질에 직접 영향
- 버전: `1.22.3` (SPM lock: `Package.resolved`)

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Reducer/AppLifecycleFeature.swift`

### swift-dependencies

- 역할: 의존성 주입(DependencyKey), 테스트/프리뷰에서 환경 분리
- 선정 이유: TCA와 결합이 표준화되어 있고, 전역 싱글톤을 피하기 쉬움
- 주의점: dependency 값이 런타임 전역처럼 사용되지 않도록 Feature 경계에서만 주입
- 버전: `1.10.0` (SPM lock: `Package.resolved`)

### Logging / OSLog

- 역할: 로그 출력/수집 추상화
- 선정 이유: 개발/배포 환경에서 관측 가능한 로그를 표준 포맷으로 남기기 위함
- 주의점: 민감 정보(토큰/경로/PII) 로깅 금지
- 버전: `swift-log 1.8.0` (SPM lock) + `OSLog`(시스템 프레임워크)

### SwiftUI-Introspect

- 역할: SwiftUI에서 AppKit 컴포넌트에 접근/튜닝
- 선정 이유: SwiftUI 표준 API로 부족한 영역을 보완
- 주의점: OS/SDK 변경에 취약할 수 있어 사용 범위를 최소화
- 버전: `26.0.0` (SPM lock)

### Sparkle

- 역할: macOS 앱 업데이트 프레임워크
- 선정 이유: 데스크톱 앱 업데이트/배포 채널에 검증된 생태계
- 주의점: 서명/노타라이즈/앱캐스트 등 배포 파이프라인과 강하게 결합
- 버전: `2.8.1` (SPM lock)

### Inject / InjectionNext

- 역할: 개발 중 SwiftUI 코드 인젝션(핫 리로딩)
- 선정 이유: UI 반복 속도 개선
- 주의점: Debug 한정 설정/제약이 있으므로 Release에 영향이 없도록 분리 유지
- 버전
    - `Inject 1.5.2` (SPM lock)
    - `InjectionNext 1.4.3` (SPM lock)

### Sentry (sentry-cocoa)

- 역할: 크래시/에러 리포팅 및 관측성(Observability)
- 선정 이유: 현장 재현이 어려운 오류의 단서 확보
- 주의점: 파일 경로/개인정보/시크릿이 이벤트에 포함되지 않도록 데이터 최소화
- 버전: `9.2.0` (SPM lock)

---

## Helper (VoyagerHelper 타깃)

Helper는 (1) 백엔드 프로세스 실행/상태 브로드캐스트, (2) 파일 인덱싱과 로컬 DB 관리, (3) 런타임 환경 로딩을 담당합니다.

### XPC (프로세스 분리)

- 역할: 메인 앱과 Helper를 분리하여 권한/프로세스 수명주기/작업 부하를 격리
- 선정 이유: 인덱싱/백엔드 실행은 장시간 작업이므로 UI 프로세스와 분리하는 것이 안전
- 주의점
    - XPC 경계에서 데이터 구조가 커지면 성능/안정성에 영향
    - 오류/재시작 시나리오를 기본값으로 설계(헬스체크, 재시작, 상태 동기화)
- 버전: 시스템 프레임워크 (핀 없음)

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift`

### ProcessRunner (백엔드 실행)

- 역할: 백엔드 실행 모드에 따라 프로세스를 실행/관찰
    - source 모드: `uv run <env>` 실행
    - bundled 모드: 앱 번들 리소스의 `server/server.bin` 실행
- 선정 이유: 개발(빠른 반복)과 배포(독립 실행) 요구를 같은 코드 경로로 묶기 위함
- 주의점
    - 백엔드 stdout/stderr를 그대로 전달하면 민감 정보가 로그에 남을 수 있음
    - 프로세스 크래시/포트 충돌/헬스체크 실패에 대한 재시도 정책이 필요
- 버전: 내부 구현

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift`

### PortReservationService (동적 포트 예약)

- 역할: 로컬 백엔드의 포트를 동적으로 할당하고 충돌을 방지
- 선정 이유: 기본값을 `PUBLIC_BACKEND_PORT=0`으로 두고, 여러 실행 환경에서 안전하게 포트를 확보
- 주의점: 예약-실행 사이 레이스 컨디션에 취약할 수 있으므로 예약/검증/재시도를 함께 설계
- 버전: 내부 구현

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/PortReservationService.swift`

### SwiftDotenv (환경 파일 로딩)

- 역할: `.env.*` 파일을 로드하고 런타임 키를 조회/주입
- 선정 이유: macOS/Helper/Backend가 동일한 키 체계를 공유하도록 하기 위함
- 주의점
    - `.env.dev`는 시크릿 포함 가능(로컬 전용)하므로 커밋 금지
    - 키 우선순위/overwrite 정책을 명확히 유지
- 버전: `2.1.0` (SPM lock)

관련 코드

- `apps/macos/Voyager/Shared/EnvironmentLoader.swift`
- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Environment.swift`

### GRDB (SQLite)

- 역할: 인덱싱 결과/상태를 로컬 SQLite에 저장/조회
- 선정 이유
    - 성능/제어/마이그레이션(직접 SQL) 측면에서 macOS 로컬 데이터에 적합
    - 인덱싱 작업에서 대량 upsert/조회가 많아 명시적 접근이 유리
- 주의점
    - 스키마/마이그레이션 관리가 앱 품질에 직접 영향
    - 스레드/큐 설정을 잘못하면 deadlock/성능 저하가 발생
- 버전: `6.29.3` (SPM lock)

관련 코드

- `apps/macos/Voyager/VoyagerHelper/Infrastructure/Database/DatabaseManager.swift`

---

## Backend (FastAPI + Python)

백엔드는 검색 API를 제공하고, 자연어 쿼리를 구조화된 검색 조건으로 변환합니다.

### FastAPI

- 역할: HTTP API 서버(라우팅, DI, 요청/응답)
- 선정 이유: 타입 기반(Pydantic)으로 API 계약을 관리하기 쉬움
- 주의점: API 계약(응답 envelope, 에러 코드)은 규칙 문서와 일관성을 유지
- 버전: `0.116.1` (`apps/backend/pyproject.toml` pin)

### Uvicorn

- 역할: ASGI 서버 런타임
- 선정 이유: FastAPI 표준 런타임
- 주의점: dev auto-reload / prod 설정을 분리
- 버전: `0.35.0` (`apps/backend/pyproject.toml` pin)

관련 코드

- `apps/backend/src/app/main.py`
- `apps/backend/src/app/search/routes.py`

### SQLModel / SQLAlchemy

- 역할: DB 접근, 스키마 정의
- 선정 이유: SQLAlchemy 기반 생태계를 활용하면서도 모델 정의를 단순화
- 주의점: ORM 남용 시 성능/쿼리 예측성이 떨어질 수 있어 쿼리 가시성 유지
- 버전
    - `sqlmodel 0.0.24` (`apps/backend/uv.lock`)
    - `sqlalchemy 2.0.43` (`apps/backend/uv.lock`)

### Pydantic

- 역할: 요청/응답 스키마, 입력 검증
- 선정 이유: FastAPI와 결합된 표준 데이터 검증 레이어
- 주의점: 에러 메시지에 민감 정보가 섞이지 않도록 sanitize
- 버전: `2.11.7` (`apps/backend/uv.lock`)

### python-dotenv

- 역할: `.env.*` 파일 로딩(백엔드)
- 선정 이유: macOS/Helper/Backend가 동일한 키를 공유하는 구조에서, 백엔드도 `.env`를 해석해야 함
- 주의점: 프로세스 환경 변수 우선 정책을 유지
- 버전: `1.1.1` (`apps/backend/uv.lock`)

### LangChain (langchain-core / langchain-openai)

- 역할: 자연어 -> 검색 조건 변환을 위한 LLM 호출/체인 구성
- 선정 이유: LLM 호출을 추상화하고 프롬프트/메시지 구조를 코드로 관리하기 쉬움
- 주의점: 비용/latency/실패율이 시스템 품질에 직접 영향을 주므로 타임아웃/재시도/관측이 중요
- 버전
    - `langchain-core 1.0.5` (`apps/backend/uv.lock`)
    - `langchain-openai 1.0.3` (`apps/backend/uv.lock`)
    - `openai 2.8.1` (`apps/backend/uv.lock`)
    - `tiktoken 0.12.0` (`apps/backend/uv.lock`)

관련 코드

- `apps/backend/src/core/llm/search_condition_converter.py`

---

## Tooling / Build

### uv (Python 패키지/런)

- 역할: Python 의존성 설치/락 관리, 개발 서버 실행
- 선정 이유: 빠른 의존성 해결과 재현 가능한 lock 기반 설치
- 주의점: 선언(>=)만 보고 버전이 떠있다고 판단하지 않기(실제 설치는 `uv.lock` 기준)
- 버전: `0.8.13` (`apps/backend/uv.lock`)

### Ruff / Pyright / pytest / pre-commit

- 역할: 코드 품질(포맷/린트), 타입 검증(strict), 테스트, 훅 자동화
- 선정 이유: Python 코드를 형식 + 타입 + 테스트로 강제해 회귀를 줄이기 위함
- 주의점: 로컬/CI에서 동일한 버전으로 실행되도록 lock과 함께 관리

버전(uv lock)

- `ruff 0.12.10`
- `pyright 1.1.405`
- `pytest 9.0.2`
- `pre-commit 4.3.0`

### Nuitka (백엔드 번들링)

- 역할: 백엔드를 독립 실행 바이너리(`server.bin`)로 컴파일(배포용)
- 선정 이유: Python 런타임/의존성을 앱 번들에 포함해 배포를 단순화
- 주의점: 빌드 시간이 길고 플랫폼 차이가 있어 smoke test 필수
- 버전: `2.8.9` (`apps/backend/uv.lock`)

관련 파일

- `scripts/build/compile-nuitka-binary.sh`
- `scripts/build/build-backend-binary.sh`

---

## 공유 리소스 (macOS <-> Backend)

### Registry JSON

- 역할: 속성/조건 정의를 단일 소스로 유지
- 선정 이유: 프론트/백이 서로 다른 해석을 하지 않도록 강제
- 주의점: 레지스트리 변경은 검색 동작 변경이므로 관련 테스트와 함께 변경

관련 파일

- `shared/property_condition_registry.json`
- `shared/system_property_registry.json`

---

## Alternatives & Trade-offs

### 상태 관리: TCA vs MVVM(+Combine)

- TCA
    - 장점: 패턴 통일, 테스트 용이, 의존성/Effect/취소가 체계적
    - 단점: 러닝 커브, 작은 화면에는 보일러플레이트가 과할 수 있음
- MVVM(+Combine)
    - 장점: 단순한 화면에서 빠름
    - 단점: 앱 전체에서 규칙이 느슨해지면 상태/이펙트가 분산되어 디버깅 비용 증가

### 백엔드 프레임워크: FastAPI vs Flask

- FastAPI
    - 장점: 타입 기반 계약(Pydantic), async 친화, 문서화 자동화
    - 단점: 모듈 구조가 커지면 규칙 합의가 필요
- Flask
    - 장점: 단순, 자유도 높음
    - 단점: 큰 서비스로 갈수록 팀 컨벤션을 직접 만들어야 함

### ORM/모델링: SQLModel vs raw SQL

- SQLModel
    - 장점: 모델 정의 단순화
    - 단점: 복잡한 쿼리는 결국 SQLAlchemy/raw SQL로 내려가게 됨
- raw SQL
    - 장점: 쿼리 제어/성능/가시성이 높음
    - 단점: 패턴/안전장치 합의가 없으면 유지보수 비용 증가
