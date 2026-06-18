# Action Design

Voyager macOS TCA Feature 설계 시 Action enum 설계 원칙과 action 비용 인지. Action은 reducer에 "무슨 일이 일어났는지"를 전달하는 메시지이며, 이를 method처럼 사용하면 안 된다.

## 핵심 원칙

- **Action은 "what happened"로 명명하라.** 기대 효과가 아니라 발생한 사건을 이름으로 사용한다. 예: `incrementCount`(X) -> `didTapIncrementButton`(O). 이렇게 하면 reducer가 행동의 결과를 자유롭게 결정할 수 있다.
- **Action은 method가 아니다.** Action을 보내는 것은 함수 호출보다 훨씬 비용이 크다. 매 action마다 전체 reducer tree를 순회하며 scope 재계산과 equality check가 발생한다.
- **Action으로 로직을 공유하지 마라.** 두 action case가 같은 로직이 필요하면 mutating method를 State에 추가하거나 private helper를 사용한다. Action을 보내서 로직을 재사용하면 불필요한 성능 비용과 커플링이 발생한다.
- **고빈도 액션을 피하라.** Timer, mouse move, scroll event를 매번 action으로 보내지 않는다. Task/effect 내에서 조건을 체크하고 실제 State 변경이 필요할 때만 action을 보낸다.
- **Delegate action만이 공유 예외다.** `.delegate()`는 child -> parent 통신에서 유일하게 허용되는 action sharing이다.

## 의사결정 기준

### "Action 이름을 어떻게 지을까?"

```text
이 action은 "유저가 무엇을 했는가"를 나타내는가?
├── YES -> did<Event> 형태 (예: didTapSaveButton, didSwipeToDelete)
└── NO -> 이 action은 "무슨 결과가 왔는가"를 나타내는가?
    ├── YES -> <Resource><Event> 형태 (예: searchResponse, userUpdated)
    └── NO -> system/internal event? (예: didBootstrap, delegate action)
```

### "Action을 보내서 로직을 재사용해도 되는가?"

```text
두 action case가 같은 로직이 필요한가?
├── YES -> State에 mutating method를 추가:
│         extension State { mutating func syncFromCache() { ... } }
│         그리고 각 케이스에서 method 호출
└── NO -> OK, 각각 별도 처리

Child reducer가 parent에 이벤트를 알려야 하는가?
├── YES -> delegate action 사용 (case delegate(Delegate))
└── NO -> child scope routing + parent 내부 처리
```

### "고빈도 액션을 어떻게 처리할까?"

```text
매 ms마다 발생하는 이벤트인가?
├── YES -> View의 @State나 로컬에서 1차 필터링:
│         .onHover { if condition { store.send(.hoverEntered) } }
└── NO -> 계속

Effect가 주기적으로 State를 체크해야 하는가?
├── YES -> Timer effect를 reducer가 아닌 task에서 실행:
│         .run { send in for await _ in timer { /* 체크 */ } }
│         변경이 필요할 때만 send
└── NO -> OK, 정상 action 흐름
```

## 코드 사례

### Action naming: "what happened"

```swift
// BAD: 기대 효과로命名
enum Action {
    case incrementCount          // "무슨 일이?" -> "count 증가"
    case showError(String)       // "무슨 일이?" -> "error 표시"
}

// GOOD: 발생한 사건으로命名
enum Action {
    case didTapIncrementButton   // 유저가 버튼을 탭했다
    case searchResponse(Result<[Item], Error>)  // 검색 결과가 도착했다
    case didDismissError         // error가 dismiss되었다
}

// Reducer에서 "what happened"를 받아서 비즈니스 로직 처리
var body: some Reducer<State, Action> {
    Reduce { state, action in
        switch action {
        case .didTapIncrementButton:
            state.count += 1
            // 추가 로직: analytics, haptic, validation 등을 자유롭게 추가 가능
            return .none
        case .searchResponse(.success(let items)):
            state.items = items
            return .none
        case .searchResponse(.failure(let error)):
            state.error = error.localizedDescription
            return .none
        }
    }
}
```

### 고빈도 액션 회피

```swift
// BAD: Timer가 매 초마다 action을 reducer로 보냄
Reduce { state, action in
    switch action {
    case .timerTick:
        // 매초 체크 -> 불필요한 action 트래픽
        if state.shouldRefresh {
            return .run { send in await send(.refresh) }
        }
        return .none
    }
}
```

```swift
// GOOD: Effect 내에서 조건 체크, 필요할 때만 action
case .startMonitoring:
    return .run { send in
        for await _ in timer(interval: .seconds(1)) {
            // Effect 내부에서 조건 체크
            if await shouldRefresh() {
                await send(.refreshNeeded)
            }
        }
    }
```

### Delegate로 child-parent 통신

```swift
// GOOD: Child가 delegate action으로 parent에 알림
@Reducer
struct ItemRowFeature {
    @ObservableState
    struct State: Equatable { ... }

    enum Action {
        case didTapDeleteButton
        case delegate(Delegate)

        enum Delegate {
            case didConfirmDelete
        }
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .didTapDeleteButton:
                state.showConfirmation = true
                return .none
            case .delegate:
                return .none
            }
        }
    }
}

// Parent가 delegate만 관찰
var body: some Reducer<State, Action> {
    Scope(state: \.rows, action: \.rows) {
        ItemRowFeature()
    }
    Reduce { state, action in
        switch action {
        case .rows(.delegate(.didConfirmDelete)):
            // Parent가 child 대신 삭제 처리
            state.removeDeletedItem()
            return .run { _ in /* API 호출 */ }
        default:
            return .none
        }
    }
}
```

### Action으로 로직 공급 금지

```swift
// BAD: Action을 method처럼 사용
enum Action {
    case applyFilter(FilterType)
    case refreshData
}

// applyFilter가 refreshData와 같은 로직을 공유해야 한다면
Reduce { state, action in
    switch action {
    case .applyFilter(let filter):
        state.filter = filter
        return .send(.refreshData)  // Action을 "호출"하고 있음 -> 성능 저하 + 커플링
    case .refreshData:
        state.data = computeData(filter: state.filter)
        return .none
    }
}
```

```swift
// GOOD: State method로 추출
@ObservableState
struct State {
    var filter: FilterType = .all
    var data: [Item] = []

    mutating func refreshData() {
        data = computeData(filter: filter)
    }
}

Reduce { state, action in
    switch action {
    case .applyFilter(let filter):
        state.filter = filter
        state.refreshData()   // State method 호출 -> action 비용 없음
        return .none
    case .refreshData:
        state.refreshData()
        return .none
    }
}
```

## 관련 문서

- `state-modeling.md` -- State 설계 원칙
- `performance.md` -- Action cost 상세
- `anti-patterns.md` -- Action anti-pattern
- `effects.md` -- Side-effect 규칙
