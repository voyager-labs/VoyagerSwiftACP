# State Modeling

Voyager macOS TCA Feature 설계 시 State 구조와 데이터 모델링 패턴. State의 생명주기, scope 성능, Optional State 활용, computed property 위험성, UI State 분리 기준을 다룬다.

## 핵심 원칙

- **State는 최소화하라.** Feature가 필요로 하는 가장 작은 State로 시작하고, 필요할 때만 확장한다.
- **Optional State로 조건부 작업을 방지하라.** State가 항상 존재하면 reducer와 effect가 불필요하게 실행된다. Optional + `ifLet`으로 필요할 때만 실행한다.
- **scope 함수는 매 action마다 호출된다.** scope 내 계산은 반드시 가벼워야 한다. O(n) 연산도 hot path에서는 문제가 된다.
- **UI State는 View 계층에 두라.** reducer State에 두면 불필요한 action/effect 트래픽이 발생한다.
- **computed property는 scope에서 절대 사용하지 마라.** TCA 1.5+에서 scoped store는 매 access마다 root store에서 변환하므로 computed property가 매번 재생성된다.

## 의사결정 기준

### "이 State는 reducer가 가져야 하는가?"

```text
State가 UI 전용인가? (hover, drag offset, animation progress)
├── YES -> @State in View (reducer 불필요)
└── NO -> reducer State 계속

State가 비즈니스 로직에 필요한가?
├── YES -> reducer State 유지
└── NO -> view만 필요하므로 @State로 이동

State 변경이 action을 트리거해야 하는가?
├── YES -> reducer State 유지
└── NO -> view의 @State로 충분
```

### "Optional State로 만들어야 하는가?"

```text
해당 State가 항상 화면에 보이는가?
├── YES -> 일반(non-optional) State
└── NO -> Optional State + ifLet

해당 State의 reducer/effect가 보이지 않을 때도 실행되어야 하는가?
├── YES -> 일반 State (예: 백그라운드 업데이트)
└── NO -> Optional State (불필요한 작업 방지)
```

### "어떤 scope 방식을 선택할까?"

```text
자식 State가 stored property인가?
├── YES -> scope(state:action:) 직접 사용 (가장 빠름)
└── NO (computed property) ->
    ├── computed property를 stored property로 리팩토링 가능?
    │   ├── YES -> stored property로 변경
    │   └── NO -> view layer에서 필요한 데이터만 계산, scope 사용 금지
```

## 코드 사례

### Optional State로 불필요한 작업 방지

```swift
// BAD: State가 항상 존재 -> 보이지 않을 때도 reducer/effect 실행
@ObservableState
struct State {
    var commandBar: CommandBarFeature.State = .init()
}

// GOOD: Optional State -> ifLet으로 필요할 때만 실행
@ObservableState
struct State {
    @Presents var commandBar: CommandBarFeature.State?  // nil이면 child reducer 미실행
}
```

```swift
var body: some Reducer<State, Action> {
    Reduce { state, action in
        // Core logic
        return .none
    }
    .ifLet(\.$commandBar, action: \.commandBar) {
        CommandBarFeature()
    }
}
```

### UI State는 View 계층에

```swift
// BAD: UI-only state가 reducer에 있음
@ObservableState
struct State {
    var sidebarHoveredItemId: UUID?  // hover는 순수 UI 상태
}

// GOOD: View에서 관리
struct SidebarView: View {
    @State private var hoveredItemId: UUID?  // View 소유
    let store: StoreOf<SidebarFeature>

    var body: some View {
        List(store.items) { item in
            RowView(item: item)
                .onHover { isHovered in
                    hoveredItemId = isHovered ? item.id : nil
                }
        }
    }
}
```

### scope는 반드시 stored property로

```swift
// GOOD: stored property로 scope
@ObservableState
struct State {
    var settings: SettingsFeature.State = .init()
}

// ParentView
ChildView(
    store: store.scope(state: \.settings, action: \.settings)  // 직접 key path
)
```

```swift
// BAD: computed property로 scope
extension ParentFeature.State {
    var computedSettings: SettingsFeature.State {
        SettingsFeature.State(
            // 매번 재생성되는 계산
        )
    }
}

// scope 호출 시마다 computedSettings가 재계산됨
ChildView(
    store: store.scope(state: \.computedSettings, action: \.settings)  // 성능 저하
)
```

### State 변화 감지 비용 인지

```swift
// BAD: UserDefaults를 scope 함수에서 참조
var body: some Reducer<State, Action> {
    Scope(state: \.child, action: \.child) {
        // scope closure 내부에서 UserDefaults 읽기 -> action마다 호출
    }
}

// scope closure는 외부 상태를 참조하지 않고 State만 사용해야 함
```

## 관련 문서

- `action-design.md` -- State 변화를 유발하는 action 설계
- `performance.md` -- State scope의 성능 비용
