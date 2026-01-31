---
name: macos-tca-orchestrator
description: 대형 TCA Feature를 부모(오케스트레이터) + 하위 리듀서 주입 패턴으로 분해합니다 (View는 부모 Action만 send).
compatibility: opencode
metadata:
  area: macos
  pattern: tca-orchestrator
---

TCA Feature(리듀서)가 커져서 파일이 과도하게 길어지거나, `Feature+Something.swift` 같은 extension 분산이 늘어날 때 사용하는 리팩터링 스킬입니다.

## 목표

- 상위 부모 리듀서를 단일 진입점으로 유지(Controller 역할)
- 관심사별 하위 리듀서(서비스/컨트롤러 유사)를 분리하고 init으로 주입
- View는 부모 `Action`만 send 하도록 유지

## 적용 기준(신호)

- 하나의 Feature 파일이 비정상적으로 길어짐(상태/액션/이펙트/유틸 혼재)
- 책임이 섞임: 네비게이션/로딩/선택/네트워크/캐시/로깅이 한 파일에 공존
- extension 파일이 늘면서 로직 위치 추적이 어려움

## 설계 절차

1) 책임 분해

- 예: `Navigation`, `Loading`, `Selection`, `Commands`, `SideEffects`
- 하위 리듀서는 “입력: (State, Action) / 출력: Effect<Action>” 형태로 고정합니다.

2) Action은 부모 기준으로 유지

- View에서 보내는 액션은 부모 액션만.
- 필요하면 부모 `Action` 내부에 하위 도메인 액션을 케이스로 래핑합니다.

3) 하위 리듀서 정의

하위 리듀서는 TCA `Reducer`가 아니라, 얇은 reducer object로 두는 것을 기본으로 합니다.

```swift
import ComposableArchitecture

struct <Slice>NavigationReducer {
  func reduce(into state: inout <Slice>State, action: <Slice>Action) -> Effect<<Slice>Action> {
    // navigation concerns...
    return .none
  }
}
```

4) 부모(오케스트레이터)에서 주입 + merge

```swift
import ComposableArchitecture

@Reducer
struct <Slice>Feature {
  typealias State = <Slice>State
  typealias Action = <Slice>Action

  let navigation: <Slice>NavigationReducer
  let loading: <Slice>LoadingReducer

  init(
    navigation: <Slice>NavigationReducer = .init(),
    loading: <Slice>LoadingReducer = .init()
  ) {
    self.navigation = navigation
    self.loading = loading
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      .merge(
        navigation.reduce(into: &state, action: action),
        loading.reduce(into: &state, action: action)
      )
    }
  }
}
```

## 테스트/유지보수 포인트

- 하위 리듀서 단위로 pure하게 테스트 가능하도록 “부작용 입력(의존성)”은 부모에서 주입하거나, 하위 리듀서에 명시적으로 주입합니다.
- 동일한 `CancelID`/취소 정책은 부모가 오케스트레이션합니다.

## 금지/주의

- 단순히 extension 파일로만 분해(로직 추적 비용 증가)하지 않습니다.
- “하위 View가 하위 Action을 직접 send”하는 구조를 기본으로 하지 않습니다(부모 단일 진입점 유지).

## 참고

- 컨벤션 기준: `docs/architecture/macos-app.md`
