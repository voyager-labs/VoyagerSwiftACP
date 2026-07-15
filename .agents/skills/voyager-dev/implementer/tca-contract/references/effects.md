# Effects

Voyager macOS TCA에서 Effect 생성, 조합, 취소 전략. Effect는 reducer가 반환하는 `Effect<Action>` 값으로, 비동기 작업, 타이머, 장기 실행 작업을 캡슐화한다.

## 핵심 원칙

- **`.run { send in }`을 기본으로 사용하라.** async 작업에 적합하며, `send` closure를 통해 결과 action을 자유롭게 전송할 수 있다.
- **`.send`는 동기 delegate action에 사용하라.** 별도의 async context가 필요 없는 delegate notification에 적합하다.
- **merge로 병렬 실행, concatenate로 순차 실행하라.** `merge`는 모든 effect를 동시에 시작하고, `concatenate`는 이전 effect가 완료될 때까지 기다린다. 기본값은 `merge`.
- **State nil 시 반드시 cancellation하라.** Optional child State가 nil이 될 때, 또는 feature가 dismiss될 때 장기 실행 effect를 취소하지 않으면 메모리 누수와 예기치 않은 동작이 발생한다.
- **Long-running effect는 명시적 CancelID로 관리하라.** `.cancellable(id:)`로 effect에 ID를 부여하고, 필요 시 해당 ID로 취소한다.

## 의사결정 기준

### "어떤 Effect API를 사용할까?"

```text
async 작업이 필요한가?
├── YES -> .run { send in ... }
│         capture snapshot 필요하면 [weak self] 또는 let snapshot = state
├── NO -> delegate notification만 필요한가?
│   ├── YES -> .send(.delegate(.didFinish))
│   └── NO -> effect가 필요하지 않음 -> .none
```

### "merge vs concatenate?"

```text
여러 effect의 실행 순서가 중요한가?
├── YES -> concatenate (순차 실행, 이전 완료 후 다음 시작)
│         단, 애니메이션이나 사용자 입력 blocking이 발생할 수 있음
└── NO -> merge (병렬 실행, 대부분의 경우 권장)
    ├── 독립적인 API 호출 -> merge
    ├── 동시 타이머 -> merge
    └── fire-and-forget 작업 -> merge
```

### "effect를 취소해야 하는가?"

```text
feature가 dismiss/popped될 수 있는가?
├── YES -> .cancellable(id: CancelID, cancelInFlight: false)
├── NO -> effect가 무한히 실행되는가? (timer, observation)
│   ├── YES -> .cancellable(id:) + 명시적 취소
│   └── NO -> 취소 불필요

새로운 action이 이전 effect를 대체해야 하는가?
├── YES -> .cancellable(id: CancelID, cancelInFlight: true)
│         예: 검색어 변경 시 이전 검색 취소
└── NO -> cancelInFlight: false
```

## 코드 사례

### .run: async 작업과 결과 전송

```swift
case .didTapSaveButton:
    let item = state.currentItem

    return .run { send in
        do {
            let response = try await apiClient.save(item)
            await send(.saveResponse(.success(response)))
        } catch {
            await send(.saveResponse(.failure(error)))
        }
    }
```

### .send: 동기 delegate

```swift
// Delegate action을 즉시 전송
case .didTapDoneButton:
    return .send(.delegate(.didFinishOnboarding))
```

### merge: 병렬 실행

```swift
case .didAppear:
    return .merge(
        .run { send in await send(.loadUser) },
        .run { send in await send(.loadSettings) },
        .run { send in await send(.loadNotifications) }
    )
```

### concatenate: 순차 실행

```swift
case .didCompleteStep1:
    return .concatenate(
        .run { send in await send(.step2) },
        .run { send in await send(.step3) }
    )
```

### Cancellation: 검색어 변경 시 이전 요청 취소

```swift
enum CancelID { case searchRequest }

case .searchQueryChanged(let query):
    state.searchQuery = query
    state.debouncedQuery = query

    return .run { [query] send in
        try await Task.sleep(for: .milliseconds(300))
        let results = try await searchClient.search(query)
        await send(.searchResponse(results))
    }
    .cancellable(id: CancelID.searchRequest, cancelInFlight: true)
```

### State nil 시 자동 취소 (ifLet)

```swift
// ifLet은 child State가 nil이 될 때 자식의 모든 effect를 자동 취소
var body: some Reducer<State, Action> {
    Reduce { state, action in
        switch action {
        case .dismissButtonTapped:
            state.destination = nil  // 자동으로 destination의 모든 effect 취소
            return .none
        default:
            return .none
        }
    }
    .ifLet(\.$destination, action: \.destination) {
        DestinationFeature()
    }
}
```

### Long-running timer effect

```swift
case .startPolling:
    return .run { send in
        for await _ in timer(interval: .seconds(5)) {
            // 5초마다 체크
            if await shouldRefresh() {
                await send(.refreshNeeded)
            }
        }
    }
    .cancellable(id: CancelID.pollTimer)

case .stopPolling:
    return .cancel(id: CancelID.pollTimer)
```

### Task 내부에서 상태 스냅샷 캡처

```swift
case .didTapDelete:
    let snapshotID = state.currentItemID  // action 시점에 캡처

    return .run { send in
        do {
            try await apiClient.delete(snapshotID)
            await send(.deleteResponse(.success(snapshotID)))
        } catch {
            await send(.deleteResponse(.failure(error)))
        }
    }
    // Task 실행 중 state가 변경되어도 snapshotID는 변하지 않음
```

### 고빈도 체크는 effect 내부에서

```swift
// BAD: Timer가 매 Tick마다 action을 reducer로 전송
case .timerTick:
    if state.shouldRefresh { ... }

// GOOD: Effect 내부에서 조건 체크 후에만 action 전송
case .startMonitoring:
    return .run { send in
        for await _ in timer(interval: .seconds(1)) {
            if await conditionMet() {
                await send(.conditionMet)
            }
        }
    }
```

## Reducer 합성 순서 — Scope을 Reduce 앞에

여러 reducer를 합성할 때 `Scope(state:action:)`은 부모 `Reduce`보다 **반드시 먼저** 배치해야 한다. 그래야 부모의 delegate handler가 자식 reducer 실행 후의 갱신된 상태를 관찰할 수 있다.

TCA effect ordering 규칙:

- `Scope` effect가 `Reduce` effect보다 **먼저** 반환된다.
- 자식 reducer가 `.delegate(.recoveryRequired(...))` 같은 delegate action을 전송하면, 부모 `Reduce`가 그 delegate를 받아 처리한다.
- `Scope`이 `Reduce` 뒤에 있으면 delegate handler가 stale child state를 읽게 된다.

```swift
// GOOD: Scope이 먼저, Reduce가 나중
var body: some Reducer<State, Action> {
    Scope(state: \.accountAccess, action: \.accountAccess) {
        AccountAccessFeature()
    }
    Reduce { state, action in
        switch action {
        case .accountAccess(.delegate(.unlocked(let snapshot))):
            // 자식 reducer가 이미 상태를 갱신한 후 이 handler가 실행됨
            state.accessGatePhase = .granted
            return .send(.delegate(.openInitialWindowIfNeeded))
        default:
            return .none
        }
    }
}
```

TestStore에서 다단계 delegate chain을 테스트할 때도 이 순서가 반영된다. 자식 action(delegate 포함)을 부모 routing action보다 먼저 `receive`해야 한다.

```swift
// 다단계 chain: session expired → child가 delegate 전송 → 부모가 phase 변경
await store.send(.lifecycle(.accountAccess(._sessionExpiredDetected)))
await store.receive(\.lifecycle.accountAccess.delegate.recoveryRequired)  // 자식 delegate 먼저
await store.receive(\.lifecycle.delegate.signedOutPhaseSet)               // 그 다음 부모 routing
```

> **출처:** PR #329 Task 3-4. `kw-20260712-tca-reducer-scope-reduce`

## 관련 문서

- `action-design.md` -- Effect 결과를 받을 action 설계
- `performance.md` -- Effect 성능 고려사항
- `anti-patterns.md` -- Effect 관련 안티패턴
- `navigation.md` -- Navigation dismissal 시 자동 취소
- `observation-lifecycle-rule.md` -- Observation lifecycle 규칙
