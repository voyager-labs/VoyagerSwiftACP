# Reducer Composition

Voyager macOS 코드베이스에서 허용되는 TCA reducer composition 패턴과 선택 기준. `@Reducer` body는 `ReducerBuilder` 기반으로, body에 나열된 reducer가 **top-to-bottom 순차 실행**되며 effect는 병합된다.

## 허용 패턴

| 패턴                          | 설명                                                        | Voyager 사용 시기                                                                               |
| ----------------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `Scope(state:action:)`        | 독립 State/Action을 가진 자식 Feature를 부모 State에 임베드 | 자식 Feature가 **항상 존재**할 때. 예: OnboardingFeature 내 Welcome, AccountAccess, Permissions |
| `CombineReducers`             | 여러 Reducer를 그룹화하여 크로스커텐 modifier 적용          | 동일 Feature 내 **크로스커텐 관심사**(lifecycle, save, undo 등)에 공통 modifier가 필요할 때     |
| `Reduce`                      | 클로저 기반 인라인 reducer                                  | 별도 타입이 오버헤드인 간단 로직. 단일 Feature 내 로컬 action 처리                              |
| `.ifLet(\.state, action:)`    | Optional 자식 -- nil 시 자동 취소                           | 시트, 팝오버, 풀스크린 등 **조건부로 나타나는** 자식                                            |
| `.forEach(\.items, action:)`  | IdentifiedArray 컬렉션 자식                                 | 리스트/그리드의 **각 항목별** 독립 reducer                                                      |
| `.ifCaseLet(\.case, action:)` | Enum State 특정 케이스 -- case 전환 시 자동 취소            | loggedIn/out 같은 **배타 State 전환**                                                           |

## 의사결정 트리

```
자식이 항상 존재하는가?
├── Yes -> 자식이 독립 Feature인가?
│          ├── Yes -> Scope
│          └── No (동일 Feature 내부 로직 그룹) -> CombineReducers
└── No -> 자식이 Optional State인가?
          ├── Yes -> .ifLet
          └── No -> 자식이 컬렉션 항목인가?
                    ├── Yes -> .forEach
                    └── No -> 자식이 Enum 케이스인가?
                              ├── Yes -> .ifCaseLet
                              └── No -> Reduce (인라인)
```

### Scope vs CombineReducers 선택 기준

`Scope`와 `CombineReducers`는 서로 다른 ownership 구조를 만든다:

- **Scope**: Child가 독립적인 State/Action을 소유하고, feature 경계가 명확하며, 독립적인 테스트 가치가 있을 때.
- **CombineReducers**: 여러 관심사가 같은 parent State/Action을 공유하고, 별도 child feature 경계가 필요하지 않을 때.
- Reducer composition style을 완전히 local preference에 맡기지 않는다. Ownership shape이나 feature boundary가 바뀌면 명시적인 Scope를 선택한다.
- 동일 Feature 내 크로스커텐 관심사에 공통 modifier가 필요하면 `CombineReducers`로 래핑한다.
- Large non-trivial private helper reducer를 같은 파일에 `.merge`로 나열할 때는, dedicated reducer module이 ownership을 더 명확하게 한다면 분리를 고려한다.

### Delegate와 Child Action 경계

Scope로 compose된 owned child reducer를 parent의 `delegate` 네임스페이스 안에 넣지 않는다. Child action은 직접 case로 유지하고, `delegate`는 outward/upward event 전용으로 예약한다:

```swift
// GOOD: child action은 직접 case
enum ParentAction {
    case view(View)
    case delegate(Delegate)
    case child(ChildFeature.Action)
}

Scope(state: \.child, action: \.child) {
    ChildFeature()
}

// Parent consumes semantic child output:
// case .child(.delegate(.didFinish))
```

```swift
// AVOID: owned child routing을 parent delegate에 병합
enum ParentAction {
    case view(View)
    case delegate(Delegate)
    enum Delegate {
        case child(ChildFeature.Action)  // 이렇게 하지 않는다
        case didFinish
    }
}
```

## 비표준 패턴

**Extension Reducer 병렬 배치** -- body에 `CombineReducers` 래핑 없이 여러 reducer를 직접 나열하는 방식.

- 현재 ComposerFeature에서 사용 중
- 기능적으로 동작하나, TCA 공식 `CombineReducers` 없이 사용하는 것을 권장하지 않음
- 크로스커텐 modifier가 필요한 경우 반드시 `CombineReducers`로 래핑
- 단순 나열만으로 충분한 경우에도 일관성을 위해 `CombineReducers` 사용을 권장
- 향후 마이그레이션 시 `CombineReducers { ... }`로 래핑할 것

## 상세 사용법

### `Scope` -- 독립 Feature 임베드

Child가 항상 존재하고 독립적인 State/Action/테스트를 가질 때 사용. 직접 key path로 접근하여 가장 빠르고 안전한 composition 방식.

```swift
Scope(state: \.settings, action: \.settings) {
    SettingsFeature()
}
```

### `.ifLet` -- Optional 자식

자식 State가 Optional일 때, non-nil이면 자식 reducer 실행, nil이면 미실행. nil로 전환 시 자식의 모든 effect가 자동 취소된다. 시트, 팝오버 등 조건부 UI에 사용.

```swift
@Reducer
struct InventoryFeature {
  @ObservableState
  struct State: Equatable {
    @Presents var addItem: ItemFormFeature.State?  // non-nil = 화면에 표시
  }
  enum Action {
    case addItem(PresentationAction<ItemFormFeature.Action>)
  }
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .addButtonTapped:
        state.addItem = ItemFormFeature.State()  // non-nil로 만들면 자동 네비게이션
        return .none
      // ...
      }
    }
    .ifLet(\.addItem, action: \.addItem) { ItemFormFeature() }
  }
}
```

### `.forEach` -- 컬렉션 항목별 reducer

`IdentifiedArray`의 각 요소마다 독립 reducer를 실행. 항목 추가 시 새 reducer 생성, 삭제 시 기존 effect 자동 취소. `EmptyReducer().forEach(...)` 관용구로 no-op shell에 체인하여 사용한다.

```swift
struct Parent: Reducer {
  struct State {
    var rows: IdentifiedArrayOf<Row.State>
  }
  enum Action {
    case row(id: Row.State.ID, action: Row.Action)
  }
  var body: some Reducer<State, Action> {
    Reduce { state, action in /* 부모 로직 */ }
    .forEach(\.rows, action: /Action.row) { Row() }
  }
}
```

### `.ifCaseLet` -- Enum State 케이스별 reducer

State가 enum일 때, 특정 case에만 자식 reducer를 바인딩. case가 전환되면 이전 case의 모든 effect가 자동 취소된다. 배타적인 상태 전환(loggedIn/out, auth/unauth 등)에 사용.

```swift
struct Parent: Reducer {
  enum State {
    case loggedIn(Authenticated.State)
    case loggedOut(Unauthenticated.State)
  }
  enum Action {
    case loggedIn(Authenticated.Action)
    case loggedOut(Unauthenticated.Action)
  }
  var body: some Reducer<State, Action> {
    Reduce { state, action in /* 부모 코어 로직 */ }
    .ifCaseLet(/State.loggedIn, action: /Action.loggedIn) { Authenticated() }
    .ifCaseLet(/State.loggedOut, action: /Action.loggedOut) { Unauthenticated() }
  }
}
```

### 실행 순서 (modifier 적용 시)

`.ifLet`, `.forEach`, `.ifCaseLet`은 **자식이 먼저, 부모가 나중에** 실행되는 순서를 강제한다. 부모가 자식이 반응할 기회 없이 state를 변경(예: 컬렉션 요소 삭제, enum case 전환)하면 Xcode에 런타임 경고가 표시된다.

## Bridge/Translator Reducer

Child-to-child, child-to-window, child-to-navigation routing은 parent-owned bridge reducer나 translator reducer를 사용한다. Sibling feature 간의 직접 peer mutation은 피하고, 하나의 canonical owner를 통해 라우팅한다.

## 관련 문서

- `state-modeling.md` -- State 설계와 Scope 성능
- `action-design.md` -- Action 설계와 Delegate 규칙
- `effects.md` -- Effect cancellation과 composition
