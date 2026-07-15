# Performance

Voyager macOS TCA 성능 디버깅과 최적화. TCA는 action이 전송될 때마다 전체 reducer tree를 순회하므로 action 비용, scope 비용, State diffing 비용을 인지하고 설계해야 한다.

## 핵심 원칙

- **모든 action은 reducer tree를 순회한다.** action 하나가 전송되면 Scope/ifLet/forEach modifier가 최상단부터 최하단까지 매번 실행된다. action 수를 불필요하게 늘리면 전체 성능이 선형으로 저하된다.
- **scope 함수는 매 action마다 호출된다.** `Scope(state:action:)`의 state closure, `.ifLet`의 is-nil 체크, `.forEach`의 컬렉션 탐색이 모든 action에서 실행된다. scope 내 계산은 반드시 O(1)이어야 한다.
- **computed property로 scope하지 마라.** TCA 1.5+에서 scoped store는 root store 참조를 유지하고 access 시마다 변환한다. computed property가 매번 재생성되면 성능이 크게 저하된다.
- **고빈도 액션은 reducer까지 보내지 마라.** Timer tick, mouse move, slider drag를 action으로 보내면 reducer tree가 매번 순회된다. View layer나 effect 내부에서 1차 처리한다.
- **`_printChanges`로 action당 state 변경을 디버깅하라.** 어떤 action이 어떤 State 변화를 유발하는지, 불필요한 재렌더링이 있는지 확인하는 첫 번째 도구다.

## 의사결정 기준

### "action 비용이 문제인가?"

```text
Reducer에서 처리하는 action이 초당 10회 이상인가?
├── YES -> 고빈도 액션 의심:
│         . View에서 @State로 1차 필터링
│         . Effect 내부에서 조건 체크 후에만 send
└── NO -> OK, 정상 범위

action이 UI 반응성에 영향을 주는가?
├── YES -> _printChanges 활성화:
│         return .none 등록 후 action 경로 추적
└── NO -> OK
```

### "scope 성능이 문제인가?"

```text
scope closure에 계산이 포함되어 있는가?
├── YES -> O(1)인가?
│   ├── O(1) -> OK (단순 key path 접근)
│   └── O(n) 이상 -> scope 밖으로 이동 (pre-compute 또는 view layer로)
└── NO -> scope 자체의 overhead는 매우 작음

scope가 computed property를 사용하는가?
├── YES -> stored property로 변경
└── NO -> OK
```

### "printChanges로 무엇을 확인할까?"

```text
action이 의도치 않은 State를 변경하는가?
├── YES -> reducer 로직 버그, 불필요하게 넓은 State 변경
└── NO -> OK

action이 너무 많은 State를 변경하는가?
├── YES -> action 분리 or State 구조 개선
└── NO -> OK
```

## 코드 사례

### `_printChanges`로 action 디버깅

```swift
// Reducer에 _printChanges modifier 추가
var body: some Reducer<State, Action> {
    Reduce { state, action in
        // reducer 로직
    }
    ._printChanges()  // 모든 action의 State 변화를 콘솔에 출력
}

// 출력 예시:
// received action: .didTapIncrementButton
//   Feature.State
//     count: 0 -> 1  (변경된 property만 표시)
```

### 고빈도 액션: View에서 1차 필터링

```swift
// BAD: 매 hover 변경 시 action 전송
List(store.items) { item in
    .onHover { isHovered in
        store.send(.hoverChanged(item.id, isHovered))  // 매 프레임 전송
    }
}

// GOOD: View에서 조건 만족 시에만 action 전송
List(store.items) { item in
    .onHover { isHovered in
        if isHovered && item.shouldShowTooltip {
            store.send(.tooltipRequested(item.id))  // 실제 필요할 때만 전송
        }
    }
}
```

### 고빈도 액션: Effect 내부 처리

```swift
// BAD: Timer가 매 초 action 전송
case .timerTick:
    if state.shouldRefresh {
        return .run { send in await send(.refresh) }
    }
    return .none

// GOOD: Effect 내부에서 체크 후 필요할 때만 전송
case .startMonitoring:
    return .run { send in
        for await _ in timer(interval: .seconds(1)) {
            let needsRefresh = await checkIfRefreshNeeded()
            if needsRefresh {
                await send(.refreshNeeded)
            }
        }
    }
```

### Scope 성능: stored property 사용

```swift
// GOOD: stored property로 scope
@ObservableState
struct State {
    var settings: SettingsFeature.State = .init()
}

ChildView(
    store: store.scope(state: \.settings, action: \.settings)  // O(1) key path
)
```

```swift
// BAD: computed property로 scope
extension ParentFeature.State {
    var childState: ChildFeature.State {
        ChildFeature.State(
            items: items.filter { $0.isActive }.map { ... }  // 매번 O(n)
        )
    }
}

// scope 호출마다 computed property 재계산
ChildView(
    store: store.scope(state: \.childState, action: \.child)
)
// Badge feature count가 500+일 때 scope cost가 프레임 드롭 유발
```

### Slider/연속 값 처리

```swift
// BAD: 매 slider 변화마다 action 전송
Slider(value: $opacity, in: 0...1)
    .onChange(of: opacity) { _, newValue in
        store.send(.opacityChanged(newValue))  // 60fps로 전송
    }

// GOOD: View의 @State로 관리, 완료 시에만 action 전송
struct MyView: View {
    let store: StoreOf<Feature>
    @State var opacity = 0.5

    var body: some View {
        Slider(value: $opacity, in: 0...1) {
            // 완료(on editing end) 시에만 한 번 전송
            store.send(.opacityFinalized(opacity))
        }
    }
}
```

### \_printChanges 출력 활용

```swift
// Action이 전송될 때마다 전체 State tree를 diffing
// 변경이 없는 action은 "received action: .someAction"만 출력
// 변경이 있는 action은 변경된 property만 표시

// 문제 진단 예시:
// "received action: .refreshResponse"가 자주 출력되며
//   Feature.State
//     _lastRefreshTime: 12345 -> 12346  (의미 없는 변경)
// 이런 경우 _lastRefreshTime이 불필요하게 action을 유발하는지 확인
```

## 관련 문서

- `action-design.md` -- 고빈도 액션 설계
- `state-modeling.md` -- Scope 성능, computed property 위험성
- `anti-patterns.md` -- 성능 관련 안티패턴
- `effects.md` -- Effect 성능 고려사항
