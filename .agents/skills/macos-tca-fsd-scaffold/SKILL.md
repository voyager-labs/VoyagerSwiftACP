---
name: macos-tca-fsd-scaffold
description: Voyager(macOS)에서 TCA + FSD 컨벤션으로 새 모듈을 스캐폴딩합니다 (State/Action 분리 + typealias).
compatibility: opencode
metadata:
  area: macos
  pattern: tca-fsd
---

Voyager 타깃에서 새 모듈(Page/Feature/Entity/Widget/Shared)을 추가할 때 사용하는 스캐폴딩 스킬입니다.

## 입력(필수)

- FSD Layer: `App | Pages | Widgets | Features | Entities | Shared`
- Slice 이름: `UpperCamelCase` (예: `FileManager`, `Composer`)
- Segment 필요 여부: `Api/Model/Reducer/Ui/Lib/Config` 중 최소 세트

## 기본 규칙

- 폴더 구조는 FSD 스타일을 따르되, 실제 코드는 TCA(`@Reducer`, `@ObservableState`)를 중심으로 구성합니다.
- 새 모듈은 `State`/`Action`을 `Model/`로 분리하고, `Reducer/`에서는 `typealias`로 주입합니다.
- UI(View)는 가능하면 “부모 Feature의 Action”만 send 합니다. 하위로 쪼개질 때는 `Scope` 또는 오케스트레이터 패턴을 사용합니다.

## 레이어 → 경로 매핑

- App: `apps/macos/Voyager/Voyager/01_App/<Segment>/...`
- Pages: `apps/macos/Voyager/Voyager/02_Pages/<Slice>/<Segment>/...`
- Widgets: `apps/macos/Voyager/Voyager/03_Widgets/<Slice>/<Segment>/...`
- Features: `apps/macos/Voyager/Voyager/04_Features/<Slice>/<Segment>/...`
- Entities: `apps/macos/Voyager/Voyager/05_Entities/<Slice>/<Segment>/...`
- Shared: `apps/macos/Voyager/Voyager/06_Shared/<Segment>/...`

Segment 권장

- `Model/`: State/Action/도메인 타입
- `Reducer/`: Reducer 조립(오케스트레이션)
- `Ui/`: View
- `Api/`: TCA dependency client, 외부 연동
- `Lib/`: 헬퍼/유틸(확장자 기반 네이밍)
- `Config/`: UI 토큰/설정

## 생성할 파일(최소 세트)

아래 3개는 기본 세트입니다.

1) `Model/<Slice>State.swift`

```swift
import ComposableArchitecture

@ObservableState
struct <Slice>State: Equatable {
  // TODO: state...
}
```

2) `Model/<Slice>Action.swift`

```swift
import ComposableArchitecture

@CasePathable
enum <Slice>Action: Sendable {
  // TODO: actions...
}
```

3) `Reducer/<Slice>Feature.swift`

```swift
import ComposableArchitecture

@Reducer
struct <Slice>Feature {
  typealias State = <Slice>State
  typealias Action = <Slice>Action

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      default:
        return .none
      }
    }
  }
}
```

선택(필요 시)

- `Ui/<Slice>View.swift`: `StoreOf<<Slice>Feature>`를 받아 렌더
- `Api/<Slice>Client.swift`: `DependencyKey`/`DependencyValues`로 주입

## 주의사항

- `@Reducer`가 중첩 `Action`에 자동 적용하던 `@CasePathable`은 typealias 방식에서는 자동 주입되지 않을 수 있으므로, 외부 `Action` enum에 `@CasePathable`을 명시합니다.
- `@ObservableState`도 외부 `State`에 명시합니다.

## 커질 때의 확장 전략

- 파일이 커지면 `extension` 파일을 무한정 늘리기보다, 부모(오케스트레이터) + 하위 리듀서 주입 패턴으로 분해합니다.
- 자세한 패턴은 `docs/architecture/macos-app.md`를 기준으로 하고, 필요하면 `macos-tca-orchestrator` 스킬을 사용합니다.

## 참고

- 아키텍처 기준: `docs/architecture/macos-app.md`
