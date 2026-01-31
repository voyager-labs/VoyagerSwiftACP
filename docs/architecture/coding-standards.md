# 코딩 표준 및 스타일 가이드

이 문서는 Voyager 프로젝트의 Python(백엔드)과 Swift(macOS) 코드 작성 표준을 정의합니다. 모든 코드는 일관성, 가독성, 유지보수성을 위해 이 가이드를 준수해야 합니다.

## 목차

1. [공통 원칙](#공통-원칙)
2. [Python 코딩 표준](#python-코딩-표준)
3. [Swift 코딩 표준](#swift-코딩-표준)
4. [에러 처리 패턴](#에러-처리-패턴)
5. [테스트 가이드라인](#테스트-가이드라인)
6. [코드 리뷰 체크리스트](#코드-리뷰-체크리스트)
7. [설정 파일 표준](#설정-파일-표준)

---

## 공통 원칙

### 언어 정책

- **문서/대화**: 한국어 사용
- **코드/식별자/명령**: 영어 사용
- **코드 주석**: 한국어로 작성 (비즈니스 로직 설명)
- **커밋 메시지**: Conventional Commits (`feat:`, `fix:`, `chore:` 등)

### 기본 원칙

- **명확성 > 간결성**: 이해하기 쉬운 코드가 짧은 코드보다 우선
- **일관성**: 기존 코드 패턴을 따르며, 새로운 패턴 도입 시 팀과 협의
- **타입 안전성**: 명시적 타입 선언을 통해 런타임 오류 예방
- **단일 책임**: 함수/클래스는 하나의 명확한 목적만 수행

### 보안 및 환경

- 시크릿/환경 파일(`.env`, `.env.dev`) 절대 커밋 금지
- API 키, 토큰은 환경 변수를 통해 주입
- 로그에 민감 정보(비밀번호, 토큰, 개인정보) 포함 금지

### 커밋 및 PR 규칙

- **Conventional Commits** 사용: `<type>(<scope>): <description>`
    - 타입: `feat`, `fix`, `ui`, `refactor`, `style`, `docs`, `chore`, `test`, `ci`, `build`
    - 스코프: 모노레포 명확성을 위해 `(backend)` 또는 `(macos)` 권장
    - 예시: `feat(backend): add asset ingestion endpoint`
- Swift와 Python 변경은 가능하면 분리 (강하게 결합된 경우만 예외)
- PR 설명에 의도/범위/리스크/검증 증거 포함

---

## Python 코딩 표준

### 포맷팅 (Ruff)

**설정** (`pyproject.toml`):

```toml
[tool.ruff]
line-length = 100
target-version = "py313"

[tool.ruff.lint]
select = ["FAST"]
extend-select = ["I"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
line-ending = "lf"
skip-magic-trailing-comma = false
```

**규칙**:

- **줄 길이**: 최대 100자
- **인덴트**: 공백 4개 (스페이스)
- **따옴표**: 쌍따옴표(`"`) 사용
- **라인 엔딩**: LF (`\n`)
- **임포트 정렬**: `extend-select = ["I"]`로 자동 정렬

**예시**:

```python
# 좋은 예
from collections.abc import Awaitable, Callable
from contextlib import asynccontextmanager

import setproctitle
from fastapi import FastAPI, Request, Response

from app.config import get_db_config, load_config
from infra.db.engine import engine_manager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 환경 변수 기반 설정 로드
    cfg = load_config()
    app.state.config = cfg
    yield
    # 종료 시 DB 연결 정리
    engine_manager.dispose()
```

### 타입 힌트 (Pyright Strict Mode)

**설정** (`pyproject.toml`):

```toml
[tool.pyright]
typeCheckingMode = "strict"
reportMissingTypeStubs = "none"
pythonVersion = "3.13"
reportUnnecessaryTypeIgnoreComment = "error"
reportUnnecessaryCast = "error"
reportUnreachable = "error"
```

**규칙**:

- **Strict Mode**: 모든 함수에 명시적 타입 힌트 필수
- **반환 타입**: 함수 정의 시 반환 타입 반드시 명시
- **제네릭**: `list[str]`, `dict[str, int]` 등 구체적 타입 사용
- **Optional**: `str | None` (Python 3.10+ 스타일) 사용

**예시**:

```python
# 좋은 예
async def query_search(
    request: QuerySearchRequest,
    service: SearchService = Depends(get_search_service),
) -> SearchResponse:
    """쿼리 기반 검색

    자연어 쿼리를 LLM이 해석하여 검색 조건으로 변환합니다.
    """
    return await service.query_search(
        query=request.query,
        filters=request.filters,
    )


# 나쁜 예 - 타입 힌트 없음
def process_data(data):  # ❌ 타입 없음
    return data.value
```

### 임포트 순서

1. **표준 라이브러리** (`import os`, `from pathlib import Path`)
2. **서드파티** (`from fastapi import FastAPI`)
3. **로컬/프로젝트** (`from app.config import load_config`)

각 그룹 사이에 빈 줄 1개, 그룹 내에서는 알파벳 순 정렬

### 함수 및 클래스 설계

**함수**:

- **단일 책임**: 하나의 함수는 하나의 작업만 수행
- **매개변수**: 4개 이상은 데이터 클래스/모델 사용 고려
- **문서화**: 모든 public 함수에 docstring 작성 (Google 스타일)

**클래스**:

- **명명**: `UpperCamelCase` (예: `SearchService`, `ConditionBuilder`)
- **메서드**: `lower_snake_case` (예: `build_clause`, `query_search`)
- **상수**: `UPPER_SNAKE_CASE` (모듈 레벨)

**예시**:

```python
class ConditionBuilder:
    """검색 조건을 SQL 절로 변환하는 빌더"""

    def build_clause(
        self,
        property_key: str,
        operator: str,
        value: list[str] | str | None,
    ) -> tuple[str, dict[str, Any]]:
        """단일 조건을 SQL 절과 파라미터로 변환

        Args:
            property_key: 속성 키
            operator: 연산자 (eq, ne, gt, lt, btw 등)
            value: 비교 값

        Returns:
            (SQL 절, 파라미터 딕셔너리) 튜플
        """
        # 구현...
```

### FastAPI 및 Pydantic

**라우터**:

- 명확한 태그와 프리픽스 사용
- 응답 모델 명시
- 의존성 주입으로 서비스 계층 분리

**예시**:

```python
from fastapi import APIRouter, Depends

router = APIRouter(prefix="/collection", tags=["collection"])


@router.post("", response_model=SearchResponse)
async def query_search(
    request: QuerySearchRequest,
    service: SearchService = Depends(get_search_service),
) -> SearchResponse:
    """쿼리 기반 검색"""
    return await service.query_search(
        query=request.query,
        filters=request.filters,
    )
```

**Pydantic 모델**:

- 필드별 명확한 타입과 기본값
- 필드 설명은 주석보다 `Field(description=...)` 사용
- 검증 로직은 `@validator` 또는 `@field_validator` 사용

---

## Swift 코딩 표준

### 기본 스타일

**Xcode 기본 스타일 준수**:

- **인덴트**: 공백 4개
- **줄 길이**: 120자 권장 (Xcode 기본)
- **줄 엔딩**: LF

**명명 규칙**:

- **타입**: `UpperCamelCase` (예: `FileManagerFeature`, `EntryClient`)
- **함수/변수**: `lowerCamelCase` (예: `loadItems`, `currentPath`)
- **상수**: `lowerCamelCase` (예: `let defaultIconSize = 64`)
- **프로토콜**: `UpperCamelCase` (예: `DependencyKey`)
- **열거형**: `UpperCamelCase` (예: `ViewLayout`, `SortOrder`)

**예시**:

```swift
// 좋은 예
@Reducer
struct FileManagerFeature {
    @ObservableState
    struct State: Equatable {
        var navigationState: FileManagerNavigationUtils.NavigationState = .folder("/")
        var viewLayout: ViewLayout = .list
        var sortKey: SortKey = .name
    }

    enum ViewLayout: String, Equatable, Codable {
        case list
        case grid
    }
}
```

### TCA (The Composable Architecture) 규칙

**Reducer 구조**:

- `@Reducer` 매크로 사용
- `State`는 `@ObservableState` 적용 및 `Equatable` 준수
- `Action`은 `Sendable` 준수

**State/Action 분리 패턴** (권장):

```swift
// Model/ 파일에 정의
@ObservableState
struct FileManagerState: Equatable {
    var navigationState: NavigationState
    var entries: EntriesState
}

@CasePathable
enum FileManagerAction: Sendable {
    case onAppear
    case navigateTo(String)
    case entries(EntriesAction)
}

// Reducer/ 파일에 정의
@Reducer
struct FileManagerFeature {
    typealias State = FileManagerState
    typealias Action = FileManagerAction

    var body: some Reducer<State, Action> {
        // 구현...
    }
}
```

**의존성 주입**:

- `@Dependency`를 통해 클라이언트 주입
- 글로벌 싱글톤 사용 금지

```swift
@Reducer
struct FileManagerFeature {
    @Dependency(\.entryClient)
    var entryClient
    @Dependency(\.sidebarClient)
    var sidebarClient
}
```

**Effect 및 취소**:

- 장기 실행 Effect는 취소 ID 지정
- `.cancellable(id:)` 사용

```swift
return .run { [url] send in
    do {
        let file = try await collectionFileClient.load(url)
        await send(.collectionFileLoaded(.success(file)))
    } catch {
        await send(.collectionFileLoaded(.failure(error)))
    }
}
.cancellable(id: CancelID.openCollectionFile, cancelInFlight: true)
```

### FSD (Feature-Sliced Design) 폴더 구조

```
Voyager/
├── 01_App/                 # 앱 진입점
├── 02_Pages/              # 페이지/화면
│   └── FileManager/
│       ├── Reducer/       # Feature 정의
│       ├── Ui/           # SwiftUI 뷰
│       ├── Model/        # State/Action
│       ├── Api/          # 클라이언트
│       └── Lib/          # 유틸리티
├── 03_Widgets/            # 재사용 가능한 위젯
├── 04_Features/           # 독립 기능
├── 05_Entities/           # 도메인 엔티티
└── 06_Shared/             # 공유 인프라
```

**의존성 방향**:

- `App → Pages → (Widgets | Features | Entities | Shared)`
- `Widgets → (Features | Entities | Shared)`
- `Features → (Entities | Shared)`
- `Entities → Shared`
- **역방향 의존성 금지**

### 주석 및 문서화

- **한국어 주석**: 비즈니스 로직 설명은 한국어로 작성
- **TODO/FIXME**: Linear 이슈 번호 포함 (예: `// TODO: [VOY-152] 마이그레이션 필요`)

```swift
// MARK: - Navigation

mutating func navigateToFolder(_ path: String, sidebarItemName: String) {
    // 이전 경로 저장
    let previousPath = currentPath
    selectedSidebarItem = sidebarItemName

    // 히스토리 업데이트
    let snapshot = makeHistoryEntry()
    resetComposer()
    appendBackHistory(snapshot)
    forwardHistory = []
    navigationState = .folder(path)
}
```

---

## 에러 처리 패턴

### 백엔드 (FastAPI)

**응답 봉투 (Envelope)**:

- 성공: `{ "data": <payload> }`
- 오류: `{ "error": { "code": "<ERROR_KIND>", "details": "<technical details>" } }`

**HTTP 상태 코드**:

- `400`: 잘못된 요청
- `401`: 인증 필요
- `403`: 권한 없음
- `404`: 리소스 없음
- `409`: 충돌
- `422`: 검증 실패 (Pydantic)
- `429`: 요청 과다
- `5xx`: 서버 오류 (구체적인 코드 사용)

**예시**:

```python
from fastapi import HTTPException

@router.post("/query")
async def query_search(request: QuerySearchRequest) -> SearchResponse:
    try:
        return await service.search(request.query)
    except SearchServiceError as e:
        raise HTTPException(
            status_code=422,
            detail={"code": "SEARCH_FAILED", "details": str(e)}
        )
```

### 프론트엔드 (SwiftUI + TCA)

**에러 상태 관리**:

- 에러는 타입화된 구조체/열거형으로 상태에 저장
- `message` + 선택적 `suggestion` 패턴 사용

**사용자 피드백**:

- 복구 가능한 에러는 인라인 토스트/알림 사용
- 파괴적 작업은 실행 전 확인 요청
- 배치 작업은 진행률 표시 및 취소 가능하도록

**예시**:

```swift
struct ErrorState: Equatable {
    let message: String
    let suggestion: String?
}

enum Action {
    case showError(ErrorState)
    case dismissError
}

// 사용
return .run { send in
    do {
        let result = try await riskyOperation()
        await send(.operationSucceeded(result))
    } catch {
        await send(.showError(ErrorState(
            message: "작업에 실패했습니다",
            suggestion: "네트워크 연결을 확인하고 다시 시도하세요"
        )))
    }
}
```

---

## 테스트 가이드라인

### 백엔드 (pytest)

**파일 위치**: `apps/backend/tests/`
**파일명**: `*_test.py` (예: `test_condition_builder.py`)

**규칙**:

- 테스트 함수명은 `test_` 접두사 사용
- 타입 힌트 유지 (`def test_something() -> None:`)
- Given-When-Then 패턴 또는 Arrange-Act-Assert 패턴 사용
- 의존성은 fixture로 주입

**예시**:

```python
import pytest


def test_build_db_comparison_clause() -> None:
    """DB 비교 절 생성 테스트"""
    # Given
    builder = ConditionBuilder()

    # When
    clause, params = builder.build_clause(
        "uniform_type_identifier", "any", ["public.png", "public.jpeg"]
    )

    # Then
    assert clause == "uniform_type_identifier IN (:p0, :p1)"
    assert params == {"p0": "public.png", "p1": "public.jpeg"}


def test_build_where_missing_property_key_raises() -> None:
    """속성 키 누락 시 예외 발생 테스트"""
    builder = ConditionBuilder()

    with pytest.raises(ConditionBuilderError):
        builder.build_where([{"operator": "eq", "value": "png"}])
```

**실행**:

```bash
cd apps/backend
uv run pytest
```

### 프론트엔드 (XCTest + TCA TestStore)

**파일 위치**:

- 단위 테스트: `VoyagerTests/`
- UI 테스트: `VoyagerUITests/`

**규칙**:

- 테스트 메서드명은 의도 기반 접두사 사용 (예: `testDisplaysSidebar...`)
- `@MainActor` 적용
- 의존성 주입된 fake 사용 (실제 서비스 호출 금지)
- TCA `TestStore` 사용하여 상태 변화 검증

**예시**:

```swift
import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class CollectionFeatureTests: XCTestCase {
    func testApplyFiltersSkipsInactiveConditions() async {
        // Given
        let recorder = FiltersRecorder()
        let conditions = [makeActiveCondition(), makeInactiveCondition()]
        let store = makeComposerStore(recorder: recorder, conditions: conditions)

        // When
        await store.send(.applyFilters)
        await store.receive(\.filtersResponse)
        await store.finish()

        // Then
        let payload = await recorder.last()
        XCTAssertEqual(payload?.conditions.count, 1)
        XCTAssertEqual(payload?.conditions.first?.propertyKey, "name_full")
    }
}

// MARK: - Helpers

private func makeActiveCondition() -> Condition {
    Condition(
        propertyKey: "name_full",
        propertyLabel: "Name",
        propertyType: "string",
        operatorCode: "eq",
        operatorLabel: "Equals",
        operatorValueArity: 1,
        operatorValueUIKind: "singleText",
        valueType: "string",
        values: ["Report"],
        isActive: true,
    )
}
```

**실행**:

```bash
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj
```

---

## 코드 리뷰 체크리스트

### 기능 및 설계

- [ ] 단일 책임 원칙 준수 (함수/클래스가 하나의 목적만 수행)
- [ ] 새로운 기능에 대한 적절한 테스트 추가
- [ ] 에러 처리가 모든 예외 케이스를 커버
- [ ] API 변경 시 문서 업데이트

### 코드 품질

- [ ] 타입 힌트/타입 선언이 명확하고 완전함
- [ ] 함수/변수명이 의도를 명확히 표현
- [ ] 중복 코드가 없거나 적절히 추출됨
- [ ] 복잡한 로직에 주석 추가 (한국어)

### 스타일 및 포맷

- [ ] Python: Ruff 포맷팅 준수 (`uv run ruff check .`)
- [ ] Python: Pyright strict 모드 통과 (`uv run pyright`)
- [ ] Swift: Xcode 기본 스타일 준수
- [ ] Swift: SwiftLint 경고 없음
- [ ] 줄 길이 제한 준수 (Python 100자, Swift 120자)

### 보안 및 안전성

- [ ] 민감 정보(비밀번호, 토큰)가 코드/로그에 노출되지 않음
- [ ] 사용자 입력이 적절히 검증/살균됨
- [ ] 파일 경로 조작이 안전하게 처리됨

### 성능 및 효율성

- [ ] 불필요한 데이터베이스 쿼리나 API 호출이 없음
- [ ] 대용량 데이터 처리 시 스트리밍/페이지네이션 고려
- [ ] 메모리 누수 가능성 확인 (Swift)

---

## 설정 파일 표준

### TOML 파일 (`pyproject.toml` 등)

**규칙**:

- 키/섹션을 알파벳 순으로 정렬하여 diff 단순화
- 섹션은 빈 줄로 구분
- 배열은 한 줄에 하나의 항목

**예시**:

```toml
[project]
dependencies = [
  "fastapi[standard]==0.116.1",
  "langchain-core>=0.3.0",
  "pydantic>=2.11.7",
  "uvicorn[standard]==0.35.0",
]
name = "voyager-app-backend"
requires-python = ">=3.13"
version = "0.1.1"

[tool.pyright]
pythonVersion = "3.13"
reportMissingTypeStubs = "none"
typeCheckingMode = "strict"

[tool.ruff]
line-length = 100
target-version = "py313"

[tool.ruff.format]
indent-style = "space"
line-ending = "lf"
quote-style = "double"
```

### YAML 파일 (`.github/workflows/` 등)

**규칙**:

- 인덴트: 공백 2개
- 키는 알파벳 순 정렬 (단, 논리적 순서가 중요한 경우 예외)
- 문자열 값은 따옴표 사용 (특수문자 포함 시 필수)

**예시**:

```yaml
name: CI

on:
    pull_request:
        branches: [main, develop]
    push:
        branches: [main]

jobs:
    test:
        runs-on: macos-latest
        steps:
            - name: Checkout
              uses: actions/checkout@v4

            - name: Setup Python
              uses: actions/setup-python@v5
              with:
                  python-version: "3.13"
```

### 환경 변수 파일 (`.env`)

**규칙**:

- 키는 `UPPER_SNAKE_CASE`
- 값이 비어있을 때는 명시적으로 표시 (`KEY=`)
- 주석은 `#`으로 시작
- 민감 정보는 `.env.dev`에만 포함 (Git ignored)

**예시**:

```bash
# Backend Configuration
PUBLIC_BACKEND_HOST=127.0.0.1
PUBLIC_BACKEND_PORT=0
PUBLIC_BACKEND_PROCESS_NAME=voyager-server

# Database
PUBLIC_SQLITE_FILE_NAME=voyager.db

```

---

## 참고 자료

- [PEP 8 – Style Guide for Python Code](https://peps.python.org/pep-0008/)
- [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)
- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [TCA Documentation](https://pointfreeco.github.io/swift-composable-architecture/)
- [FastAPI Best Practices](https://github.com/zhanymkanov/fastapi-best-practices)

---

_마지막 업데이트: 2026-01-30_
_문서 버전: 2.0_
