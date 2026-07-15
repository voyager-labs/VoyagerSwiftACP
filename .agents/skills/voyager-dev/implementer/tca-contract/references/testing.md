# Testing

Voyager macOS TCA Feature 단위 테스트 가이드. TestStore 기반 reducer 테스트에서 action 전송, State 검증, 시간 의존성 테스트, dependency mocking을 다룬다.

## 핵심 원칙

- **Exhaustive mode를 기본으로 사용하라.** 모든 action이 예상대로 처리되었는지, 불필요한 action이 없는지 검증한다. 예상치 못한 action이 있으면 테스트가 실패하므로 리팩토링 안전성이 높아진다.
- **Non-exhaustive mode는 선택적으로 사용하라.** 통합 테스트나 외부 effect가 많은 테스트에서 보일러플레이트를 줄일 때만 사용한다. 단, 검증 범위가 좁아지므로 핵심 로직은 exhaustive mode로 검증해야 한다.
- **TestClock으로 시간 의존성을 제어하라.** `continuousClock`, `suspendingClock` 대신 `TestClock`을 사용하면 타이머, debounce, throttle을 비약적으로 테스트할 수 있다.
- **모든 외부 의존성은 testValue를 제공하라.** Voyager는 struct-of-closures 패턴을 사용하므로 test client에서 closure 동작을 자유롭게 정의할 수 있다.
- **Case key path로 action을 정확히 매치하라.** `store.send(.someAction(.caseName(value)))` 형태로 action의 associated value까지 검증한다.

## 의사결정 기준

### "Exhaustive vs Non-exhaustive?"

```text
단일 Feature의 핵심 로직을 검증하는가?
├── YES -> exhaustive (기본값, 모든 action/effect 검증)
└── NO -> 통합 테스트인가?
    ├── YES -> non-exhaustive 고려 (child action이 많을 때)
    └── NO -> exhaustive 유지

외부 system(네트워크, 파일)과의 상호작용이 많은가?
├── YES -> non-exhaustive (외부 effect 무시 가능)
└── NO -> exhaustive 유지
```

### "어떤 것을 테스트해야 하는가?"

```text
Feature 생성 직후 initial state 검증
├── 모든 필드가 예상대로 초기화되었는가?

각 action에 대한 state 변화 검증
├── action이 올바른 State 변화를 유발하는가?
├── 잘못된 action이 무시되는가?
└── 연속 action이 올바르게 처리되는가?

Effect 검증
├── effect가 올바른 action을 반환하는가?
├── cancellation이 올바르게 동작하는가?
└── error case가 올바르게 처리되는가?

시간 의존성
├── debounce/throttle이 올바른 간격으로 동작하는가?
└── timer가 올바른 주기로 실행되는가?
```

## 코드 사례

### 기본 TestStore 설정 (Voyager struct-of-closures 패턴)

```swift
import Testing

@Test("검색어 입력 시 검색 결과가 로드된다")
func testSearchQuery() async {
    let searchResults: [Item] = [.mock]

    // Voyager 패턴: struct-of-closures로 test client 생성
    let store = TestStore(
        initialState: SearchFeature.State()
    ) {
        SearchFeature()
    } withDependencies: {
        $0.searchClient.search = { query in
            return searchResults
        }
    }
}
```

### Exhaustive mode: action 전송과 State 검증

```swift
@Test("didTapIncrementButton이 count를 증가시킨다")
func testIncrement() async {
    let store = TestStore(
        initialState: Feature.State(count: 0)
    ) {
        Feature()
    }

    // action 전송 -> reducer가 실행되고 State가 변경됨
    await store.send(.didTapIncrementButton) {
        $0.count = 1  // 변경된 State만 명시
    }
    // Effect가 없다면 .none이므로 추가 검증 불필요
}
```

### Effect 검증: action 전송과 수신

```swift
@Test("저장 버튼 탭 시 API 호출 후 응답 처리")
func testSave() async {
    let store = TestStore(
        initialState: SaveFeature.State(item: .mock)
    ) {
        SaveFeature()
    } withDependencies: {
        $0.apiClient.save = { item in
            return .success(item)
        }
    }

    await store.send(.didTapSaveButton) {
        $0.isSaving = true  // 즉시 State 변경
    }

    // save 완료 후 response action 수신
    await store.receive(\.saveResponse.success) {
        $0.isSaving = false
        $0.isSaved = true
    }
}
```

### TestClock: debounce 테스트

```swift
@Test("검색어 입력 300ms 후 검색 실행")
func testSearchDebounce() async {
    let clock = TestClock()

    let store = TestStore(
        initialState: SearchFeature.State()
    ) {
        SearchFeature()
    } withDependencies: {
        $0.searchClient.search = { _ in [Item].mock }
        $0.continuousClock = clock  // TestClock 주입
    }

    await store.send(.searchQueryChanged("hello")) {
        $0.searchQuery = "hello"
    }

    // 300ms가 아직 지나지 않음 -> 검색 미실행
    await clock.advance(by: .milliseconds(250))

    // 300ms 경과 -> 검색 실행
    await clock.advance(by: .milliseconds(50))

    // 검색 결과 수신
    await store.receive(\.searchResponse)
}
```

### Error case 검증

```swift
@Test("API 실패 시 error state 설정")
func testSaveFailure() async {
    struct SaveError: Error, Equatable {}

    let store = TestStore(
        initialState: SaveFeature.State(item: .mock)
    ) {
        SaveFeature()
    } withDependencies: {
        $0.apiClient.save = { _ in
            throw SaveError()  // 의존성에서 throw
        }
    }

    await store.send(.didTapSaveButton) {
        $0.isSaving = true
    }

    await store.receive(\.saveResponse.failure) {
        $0.isSaving = false
        $0.error = "The operation couldn't be completed."
    }
}
```

### Cancellation 검증

```swift
@Test("취소 시 진행 중인 검색이 중단된다")
func testCancelSearch() async {
    let store = TestStore(
        initialState: SearchFeature.State(searchQuery: "test")
    ) {
        SearchFeature()
    }

    // 검색 시작
    await store.send(.searchQueryChanged("new query")) {
        $0.searchQuery = "new query"
    }

    // 취소
    await store.send(.didTapCancelButton) {
        $0.isSearching = false
    }

    // 취소 후 이전 검색 결과는 수신되지 않음
}
```

### Non-exhaustive mode

```swift
@Test("통합: 로그인 후 홈 화면 표시")
func testLoginFlow() async {
    let store = TestStore(
        initialState: AppFeature.State()
    ) {
        AppFeature()
    } withDependencies: {
        $0.authClient.login = { _, _ in .mockUser }
    }

    // Non-exhaustive: 외부 effect는 검증하지 않음
    store.exhaustivity = .off

    await store.send(.login(.didTapLoginButton))
    await store.send(.login(.loginResponse(.success(.mockUser))))

    // 최종 State만 검증
    store.assert { state in
        state.isLoggedIn = true
    }
}
```

### Feature별 테스트 체크리스트

```text
[ ] Initial state: 모든 프로퍼티가 올바르게 초기화되었는가?
[ ] 각 action: action 전송 후 예상 State로 변경되는가?
[ ] Edge case: 빈 배열, nil 값, 0, overflow 경계 처리
[ ] Error case: API 실패, 잘못된 입력, 네트워크 오류
[ ] Effect: 비동기 작업 결과가 올바른 action으로 반환되는가?
[ ] Cancellation: 취소 후 effect가 중단되는가? 중복 실행 방지?
[ ] Delegate: delegate action이 올바르게 전송되는가?
[ ] Side effect: 의존성 호출이 올바른 파라미터로 실행되는가?
[ ] Time: debounce/throttle/timer가 올바르게 동작하는가?
[ ] Parallel: 여러 effect가 동시에 실행될 때 race condition이 없는가?
```

## 관련 문서

- `effects.md` -- Effect cancellation 테스트
- `navigation.md` -- Navigation 테스트 패턴
- `effects.md` -- Dependency client testValue 규칙
- `../../../orchestrator/references/11-dependency-client-design.md` -- Test client 설계
- `../../spec-test-authoring/SKILL.md` -- Spec AC test 작성 및 실행/분석
