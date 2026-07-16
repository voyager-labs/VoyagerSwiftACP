# Navigation

Voyager macOS TCA에서 Navigation 패턴 선택과 구현. TCA 1.7+ 기준 tree-based(@Presents + ifLet)와 stack-based(StackState + forEach) 두 가지 주요 패턴을 다룬다.

## 핵심 원칙

- **Modal presentation은 tree-based를 사용하라.** `@Presents` macro + `PresentationAction` + `.ifLet` 조합이 sheet/alert/dialog/fullScreenCover에 적합하다.
- **Multi-level push는 stack-based를 사용하라.** `NavigationStack` + `StackState` + `StackAction` + `.forEach` 조합이 push navigation에 적합하다.
- **Dismissal 시 effect가 자동 취소된다.** `ifLet`과 `forEach`는 child State가 제거될 때 해당 child의 모든 실행 중인 effect를 자동으로 취소한다.
- **Single drill-down은 optional state + navigationDestination을 사용하라.** Tree-based 패턴의 변형으로, 단일 depth push에 적합하다.
- **Deep linking이 중요하면 stack-based를 선택하라.** StackState는 State 배열을 직접 구성할 수 있어 deep linking 구현이 쉽다.

## 의사결정 기준

### "어떤 navigation 패턴을 사용할까?"

```text
어떤 종류의 navigation인가?
├── Modal (sheet/alert/dialog/fullScreenCover)?
│   → Tree-based: @Presents + PresentationAction + ifLet
├── Single drill-down (하나의 destination)?
│   → Tree-based: optional State + navigationDestination
├── Multi-level push (NavigationStack)?
│   → Stack-based: StackState + StackAction + forEach
├── Deep linking이 중요한가?
│   → Stack-based (State 배열 직접 구성 가능)
└── NavigationStack 안에서 Modal?
    → BOTH: stack for push, tree for sheets/alerts
```

## 코드 사례

### Tree-based: @Presents + ifLet (Sheet)

```swift
@Reducer
struct ItemListFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var addItem: ItemFormFeature.State?  // non-nil = sheet 표시
        var items: [Item] = []
    }

    enum Action {
        case addItem(PresentationAction<ItemFormFeature.Action>)
        case didTapAddButton
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .didTapAddButton:
                state.addItem = ItemFormFeature.State()  // sheet 열기
                return .none

            case .addItem(.dismiss):
                // sheet가 dismiss되면 @Presents가 자동 nil 처리
                // child의 모든 effect 자동 취소
                return .none

            case .addItem(.presented(.delegate(.didSave(let item)))):
                state.addItem = nil  // 명시적 dismiss
                state.items.append(item)
                return .none

            default:
                return .none
            }
        }
        .ifLet(\.$addItem, action: \.addItem) {
            ItemFormFeature()
        }
    }
}
```

### Stack-based: StackState + forEach (NavigationStack)

```swift
@Reducer
struct AppNavigationFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<DetailFeature.State>()  // navigation stack
    }

    enum Action {
        case path(StackActionOf<DetailFeature>)
        case didTapItem(Item.ID)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .didTapItem(let id):
                state.path.append(DetailFeature.State(itemID: id))  // push
                return .none

            case .path(.element(id: _, action: .delegate(.didDelete))):
                // child의 delegate 처리
                return .none

            case .path(.popLast):
                // back navigation
                return .none

            default:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            DetailFeature()
        }
    }
}
```

```swift
// NavigationStack View
struct AppNavigationView: View {
    @Bindable var store: StoreOf<AppNavigationFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            // Root view
            ItemListView(store: store.scope(state: \.root, action: \.root))
        } destination: { store in
            // Push된 각 child view
            DetailView(store: store)
        }
    }
}
```

### Tree-based: NavigationDestination (Single drill-down)

```swift
@Reducer
struct ItemDetailFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?  // 단일 destination
    }

    enum Action {
        case destination(PresentationAction<Destination.Action>)
        case didTapEditButton
    }

    @Reducer
    enum Destination {
        case edit(EditFeature)
        case share(ShareFeature)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .didTapEditButton:
                state.destination = .edit(EditFeature.State())
                return .none
            default:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}
```

### Dismissal 자동 취소

```swift
// ifLet을 사용하면 child State가 nil이 될 때:
// 1. child reducer 실행 중단
// 2. child의 모든 실행 중인 effect 취소
// 3. child의 상태 메모리 해제

// 명시적 cancel이 필요 없음
case .didTapDismiss:
    state.detailItem = nil  // .ifLet이 자동 정리
    return .none
```

## 관련 문서

- `effects.md` -- Dismissal 시 자동 취소 상세
- `state-modeling.md` -- Optional State 설계
- `composition.md` -- ifLet/forEach composition
- `effects.md` -- Cancellation ownership
