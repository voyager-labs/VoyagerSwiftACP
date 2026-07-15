# Anti-patterns

Voyager macOS TCA 코드에서 자주 발견되는 안티패턴과 교정 방안. AI 생성 코드, 신규 TCA 사용자, 레거시 코드에서 특히 많이 발생한다.

## God Reducer

**증상:** 단일 reducer가 800줄 이상, 여러 화면의 로직을 모두 처리, 테스트가 불가능하거나 거대함.

```swift
// GOD REDUCER: 하나의 reducer가 모든 것을 처리
@Reducer
struct GodFeature {
    @ObservableState
    struct State {
        var list: [Item] = []
        var detail: Item?
        var editState: EditState = .init()
        var searchState: SearchState = .init()
        var filterState: FilterState = .init()
        // 수십 개의 State 프로퍼티...
    }

    enum Action {
        case listAction(...)
        case detailAction(...)
        case editAction(...)
        // 수십 개의 action case...
    }
    // 800+ lines...
}
```

**교정:**

1. Feature boundary 식별 -- 각 화면/도메인별 독립 @Reducer struct 추출
2. Bottom-up 분해: leaf feature부터 시작하여 중간, 최상위 순서로
3. Scope/ifLet/forEach로 명시적 composition
4. 각 child reducer는 독립적인 State/Action/테스트 보유

```swift
// GOOD: 각 boundary가 독립 reducer로 분리
@Reducer
struct ListFeature { ... }

@Reducer
struct DetailFeature { ... }

@Reducer
struct EditFeature { ... }
```

## Action을 Method처럼 사용

**증상:** 로직 재사용을 위해 action을 보내고, action chain이 길어지며, 디버깅이 어려움.

```swift
// BAD: Action을 method로 사용하여 로직 공유
Reduce { state, action in
    switch action {
    case .applyFilter(let filter):
        state.filter = filter
        return .send(.refreshList)  // Action = method call

    case .refreshList:
        state.items = computeItems(filter: state.filter)
        return .none

    case .didTapRefreshButton:
        return .send(.refreshList)  // 또 다른 호출
    }
}
```

**교정:** State의 mutating method나 private helper로 추출. Action은 오직 외부 이벤트(message)만 표현.

```swift
// GOOD: State method로 로직 추출
@ObservableState
struct State {
    mutating func refreshData() {
        items = computeItems(filter: filter)
    }
}

Reduce { state, action in
    switch action {
    case .applyFilter(let filter):
        state.filter = filter
        state.refreshData()  // State method 직접 호출
        return .none

    case .didTapRefreshButton:
        state.refreshData()
        return .none
    }
}
```

## 고빈도 액션 오용

**증상:** Timer tick, scroll offset, mouse position 등 초당 수십-수백 회 발생하는 이벤트를 action으로 reducer에 전송.

```swift
// BAD: 매 Timer tick마다 action 전송
case .startTimer:
    return .run { send in
        for await _ in timer(interval: .seconds(1)) {
            await send(.timerTick)  // 불필요한 action
        }
    }

case .timerTick:
    // 매초 reducer 실행 -> Scope/ifLet/forEach가 모두 재실행
    if state.shouldRefresh {
        return .run { send in await send(.refresh) }
    }
    return .none
```

**교정:** Effect 내부에서 조건 체크 후 필요할 때만 action 전송. 또는 View layer에서 1차 필터링.

```swift
// GOOD: Effect 내에서 조건 체크
case .startTimer:
    return .run { send in
        for await _ in timer(interval: .seconds(1)) {
            if await shouldRefresh() {
                await send(.refreshNeeded)  // 실제 필요할 때만
            }
        }
    }
```

## 누락된 Cancellation

**증상:** Feature dismiss, State nil 전환 시 장기 실행 effect를 취소하지 않아 메모리 누수와 예기치 않은 동작 발생.

```swift
// BAD: 취소 누락
Reduce { state, action in
    switch action {
    case .startLongRunningTask:
        return .run { send in
            for await value in observationStream {
                await send(.valueUpdated(value))
            }
        }
        // State가 nil이 되어도 Stream은 계속 실행
    case .didTapDismiss:
        state.detailItem = nil  // ifLet으로 자동 취소되지 않는 case
        return .none
    }
}
```

**교정:** Optional child는 ifLet/forEach 사용, 명시적 CancelID 할당, feature dismiss 시점에 cancel.

```swift
// GOOD: CancelID로 명시적 관리
case .startLongRunningTask:
    return .run { send in
        for await value in observationStream {
            await send(.valueUpdated(value))
        }
    }
    .cancellable(id: CancelID.longTask)

case .didTapDismiss:
    state.detailItem = nil
    return .cancel(id: CancelID.longTask)  // 명시적 취소
```

## Computed Property Scope

**증상:** Scope closure나 computed property로 child State를 생성하여 매 action마다 재계산.

```swift
// BAD: computed property로 scope
extension Feature.State {
    var computedChild: ChildFeature.State {
        ChildFeature.State(
            items: items.filter { $0.isActive }
        )
    }
}

// 매 action마다 computedChild 재생성
store.scope(state: \.computedChild, action: \.child)
```

**교정:** Stored property로 전환. 계산이 필요하면 pre-compute하여 stored property에 저장.

```swift
// GOOD: stored property
@ObservableState
struct State {
    var child: ChildFeature.State = .init()
}

store.scope(state: \.child, action: \.child)  // O(1) key path
```

## UI State를 Reducer State에 저장

**증상:** hover 상태, drag offset, animation progress 등 순수 UI 상태를 reducer State에 저장.

```swift
// BAD: UI State가 reducer State에 있음
@ObservableState
struct State {
    var isHovered: Bool  // reducer가 알 필요 없는 UI state
    var dragOffset: CGSize  // 매 프레임 action 발생
}
```

**교정:** View의 `@State`로 이동. reducer는 비즈니스 로직에만 집중.

```swift
// GOOD: View에서 관리
struct SidebarView: View {
    @State private var isHovered = false
    let store: StoreOf<SidebarFeature>
}
```

## Action Naming: "expected effect"

**증상:** "무슨 일이 일어났는지" 대신 "무슨 효과를 기대하는지"로 action 이름을 지음.

```swift
// BAD: 기대 효과로命名
enum Action {
    case incrementCount        // "count를 증가시켜라" (명령형)
    case showErrorMessage      // "error 메시지를 보여줘" (명령형)
}

// GOOD: 발생한 사건으로命名
enum Action {
    case didTapIncrementButton // "증가 버튼이 탭되었다"
    case didReceiveError       // "에러가 수신되었다"
}
```

## AI 생성 코드에서 흔한 실수

TCA 1.7+ 이전 패턴을 생성하는 AI의 일반적인 오류:

| 실수                                      | 설명                                     | 교정                         |
| ----------------------------------------- | ---------------------------------------- | ---------------------------- |
| `@ObservedObject` + `ViewStore`           | TCA 1.6 이전 패턴                        | `@Bindable StoreOf<Feature>` |
| `WithViewStore`                           | TCA 1.6 이전 패턴                        | `@Bindable` 직접 사용        |
| Protocol 기반 Dependency                  | TCA 1.6 이전 패턴                        | struct-of-closures           |
| `EffectOf<Action>.none`                   | `Effect<Action>.none` 불필요             | `.none`                      |
| `Effect` 대신 `.fireAndForget`            | TCA 1.6 이전                             | `.run { send in ... }`       |
| `cancel(id:)`에 `type(of: self)` 사용     | 불명확한 cancel ID                       | 명시적 `CancelID` enum       |
| `@DependencyClient`                       | Voyager 금지 규칙                        | struct-of-closures           |
| `switch` on action (case key path 미사용) | 가능하나 `.receive(\.actionName)` 미사용 | case key path 우선           |

## 관련 문서

- `action-design.md` -- Action naming 규칙
- `state-modeling.md` -- State 설계 원칙
- `effects.md` -- Cancellation 규칙
- `performance.md` -- Computed property scope 위험성
- `composition.md` -- Reducer composition 패턴
- `state-modeling.md` -- State 설계 원칙
