# Voyager Dev Layer and Segment Rules

Use this reference when deciding where Voyager code belongs across FSD layers and standard segment names.

## Table of contents

- FSD foundations
- Layer map
- Layer contracts
- Segment responsibilities
- Segment naming rule
- Dependency direction
- Review checklist

## FSD foundations

- Use the standard layer vocabulary only: `App`, `Pages`, `Widgets`, `Features`, `Entities`, `Shared`.
- Do not invent custom top-level layers when one of the existing layers already explains the ownership.
- Use only the layers that add real value for the slice; not every change needs every layer.
- Treat slices as business/domain boundaries, not technical buckets.
- The old `Processes` idea is deprecated in official FSD guidance; in Voyager, orchestration should usually live in `01_App`, `02_Pages`, or reusable `04_Features` flows instead.

## Layer map

- `01_App/`
    - App entrypoint, global commands, lifecycle, bootstrap orchestration.
    - Do not accumulate page/entity business logic here.
- `02_Pages/`
    - Window/screen containers and navigation orchestration.
    - Compose lower layers instead of implementing deep domain logic inline.
- `03_Widgets/`
    - Reusable page-internal sections.
    - Keep them presentation-focused; do not introduce independent IO-heavy flows here.
    - Do not add widget-owned `Api/` for normal cases; inject IO from upper layers instead.
- `04_Features/`
    - Use-case level functionality.
    - Do not depend on page containers.
- `05_Entities/`
    - Domain models and domain-centered reducers.
    - Never depend on `Pages` or `Features` above them.
- `06_Shared/`
    - Reusable clients, config, utilities, design tokens, and atomic components.
    - Must stay reusable from every layer.

## Layer contracts

### `01_App` contract

- Own app entrypoint, global command routing, lifecycle bootstrap, and top-level window/app orchestration.
- Compose lower layers; do not bury domain-specific business rules directly in `01_App` reducers or models.
- Prefer app-wide clients in `01_App/Api` only when the boundary is truly app-global.
- Keep page- or entity-specific state transitions outside `01_App` unless they are app-shell coordination.
- Treat `01_App` as orchestration, not as a fallback bucket for otherwise-misplaced logic.

### `02_Pages` contract

- Own screen/window container state, navigation state, and lower-layer composition.
- Compose `Widgets`, `Features`, `Entities`, and `Shared`; do not pull lower-layer logic upward into page-local helpers without reason.
- Keep page `Ui/` presentation-focused and let reducers coordinate navigation, child routing, and page-owned side effects.
- Do not implement deep entity or use-case logic inline when a lower layer should own it.
- Use pages to connect slices, not to replace slice boundaries.

### `03_Widgets` contract

- Own reusable page-internal sections and small presentation-oriented reducer/view groupings.
- Prefer `Ui`, `Model`, `Reducer`, and `Lib` only.
- Do not add `Api/` for normal widget work; inject dependencies from higher layers.
- Do not own independent navigation, network, storage, or long-running orchestration.
- If the widget starts looking like a reusable use case or domain view, move it to `Features`, `Entities`, or `Shared`.

### `04_Features` contract

- Own use-case flows and reusable behavior that should not depend on a specific page container.
- Keep feature reducers reusable across pages/windows when possible.
- Do not import or depend on `Pages` or page-local UI containers.
- Put feature-specific external boundaries in the nearest `Api/`.
- If the logic is really domain identity/model logic rather than a use case, move it to `Entities`.

### `05_Entities` contract

- Own domain models, domain-centered reducers, and domain-specific clients/helpers.
- Never depend on `Pages` or `Features` above them.
- Keep entity state, actions, and reducers centered on domain invariants rather than screen orchestration.
- If an entity type needs page wiring convenience, prefer moving that convenience into the page layer rather than importing the page type downward.
- Keep persistence or system boundaries behind entity-local `Api/` only when they are part of the domain boundary.

### `06_Shared` contract

- Own reusable tokens, config, utilities, common clients, and atomic pieces that should remain layer-agnostic.
- Do not reference app-, page-, feature-, or entity-specific types from `Shared`.
- Prefer `06_Shared/Api` only for boundaries that are genuinely cross-cutting and safe for every layer to consume.
- Keep `Shared` free of assumptions that would block package extraction or reuse.
- If code is only meaningful for one slice, it probably does not belong in `Shared`.

### Package placement decision tree

새 타입/파일을 생성하기 전에 반드시 아래 결정 트리를 따른다. 잘못된 레이어 배치는 아키텍처 부채의 주요 원인이다.

```
1. 이 코드가 2개 이상의 서로 다른 슬라이스/피처에서 재사용되는가?
   → YES: 2번으로
   → NO:  Shared가 아님. 4번으로

2. 모든 레이어(App ~ Shared)에서 의존 가능한 범용 유틸리티/계약인가?
   → YES: 06_Shared 적합. 단, 도메인 특화 지식(스키마, 프로토콜 등)이 없어야 함
   → NO:  Shared가 아님. 3번으로

3. Helper XPC 등 Host+Helper 양쪽에서 접근해야 하는 계약인가?
   → YES: 06_Shared 적합 (HelperExternalFileChangeContract 패턴)
   → NO:  Shared가 아님. 4번으로

4. 도메인 모델/엔티티 정체성과 관련된 로직인가?
   → YES: 05_Entities 적합
   → NO:  5번으로

5. 유스케이스 플로우 / 재사용 가능한 피처 동작인가?
   → YES: 04_Features 적합. 전용 패키지 생성 고려
   → NO:  6번으로

6. 특정 페이지/윈도우 컨테이너에 종속된 로직인가?
   → YES: 02_Pages 적합
   → NO:  01_App (앱 전용 셸 오케스트레이션)
```

### One-slice code detection checklist

코드가 단일 슬라이스에만 의미있는지 확인:

- [ ] 이 코드가 참조하는 도메인 개념(스키마, 프로토콜, 상태 머신 등)이 오직 하나의 피처에서만 사용되는가?
- [ ] 다른 패키지가 이 코드를 import할 필요가 없는가?
- [ ] 이 코드의 이름에 피처 특정 용어(예: `voyager://`, 특정 URL scheme)가 포함되어 있는가?

하나라도 YES라면 `06_Shared`가 아니다.

### Anti-pattern evidence (FMW-003)

| 코드                    | 잘못된 배치                    | 이유                                     | 올바른 배치                           |
| ----------------------- | ------------------------------ | ---------------------------------------- | ------------------------------------- |
| `ExternalFileURLParser` | `06_Shared/VoyagerShared/Lib/` | `voyager://` 스키마 파싱은 FMW-003 전용  | `04_Features/ExternalFileRouter`      |
| `FilePathNormalizer`    | `06_Shared/VoyagerShared/Lib/` | FMW-003 경로 정규화 전용                 | `04_Features/ExternalFileRouter`      |
| `PathProbeClient`       | `05_Entities/Entry/Api/`       | Entry 엔티티와 무관, FMW-003 시스템 경계 | `04_Features/ExternalFileRouter/Api/` |

## Segment responsibilities

- `Ui/`
    - SwiftUI rendering plus minimal user/lifecycle event wiring.
    - Do not own system observation, SDK listeners, or business orchestration.
- `Reducer/`
    - `@Reducer` composition, effect routing, cancellation ownership, child scopes.
- `Model/`
    - State, Action, domain-facing models, and screen models.
- `Api/`
    - Dependency clients and boundary adapters using `DependencyKey` / `DependencyValues`.
- `Lib/`
    - Helpers, mappers, coordinators, delegates, and utility logic.
    - If it orchestrates SDK delegates/listeners and routes into TCA, prefer `*Coordinator.swift` here.
- `Config/`
    - Static constants, design tokens, and configuration values.

## Segment naming rule

- Prefer domain-relevant segments already used in Voyager: `Ui`, `Api`, `Model`, `Reducer`, `Lib`, `Config`.
- Do not create generic organizing buckets such as `Components`, `Hooks`, `Types`, or `Utils` as default architectural segments.

## Dependency direction

- `01_App -> 02_Pages -> 03_Widgets -> 04_Features -> 05_Entities -> 06_Shared`
- `02_Pages` may compose `03_Widgets`, `04_Features`, `05_Entities`, and `06_Shared`.
- `03_Widgets -> 04_Features | 05_Entities | 06_Shared`
- `04_Features -> 05_Entities | 06_Shared`
- `05_Entities -> 06_Shared`
- Reverse dependency is forbidden.
- Same-layer cross-slice references should be treated as a smell; prefer pushing shared logic downward.

## Review checklist

- Is this file in the right layer and segment?
- Is orchestration staying in `Reducer/` or leaking into `Ui/` / `Lib/`?
- Is a new external boundary hidden behind an `Api/*Client.swift`?
- Does the dependency direction still point downward?
- Does this task also require `public-boundary-spec.md` because another slice or package-facing surface is involved?
