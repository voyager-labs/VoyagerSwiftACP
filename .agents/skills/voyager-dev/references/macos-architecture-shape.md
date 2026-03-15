# Voyager Dev macOS Architecture Shape

Use this reference as the skill-local architecture baseline when editing `apps/macos/Voyager/Voyager/**`.

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

## Slice and public API stance

- Every slice should have a stable surface for other layers or slices to compose against.
- Same-layer cross-slice collaboration should usually be composed upward in `Pages` or `App`.
- For detailed boundary, deep-import, and entity cross-reference rules, use `public-boundary-spec.md` as the canonical reference.

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

## TCA architecture stance

- Non-trivial slices should prefer split `Model/*State.swift`, `Model/*Action.swift`, and `Reducer/*Feature.swift`.
- Parent reducers should remain the main orchestration entry point.
- Detailed action layering, effect ownership, dependency-client, and cancellation rules live in `tca-contract.md`.

## Orchestrator pattern

- Keep the parent feature as the single entry point for large flows.
- Push focused concerns into child reducers or dedicated reducer types beneath the parent.
- Let views send parent-owned actions only; do not wire views directly to internal helper reducers.
- Keep cancellation ownership at the parent reducer when it orchestrates the lifecycle.

## External boundary stance

- External boundaries belong behind dependency clients, not direct system/global calls.
- App-wide or cross-cutting boundaries may live in `01_App/Api` or `06_Shared/Api`; otherwise prefer the nearest owning slice `Api/`.
- Detailed client introduction, effect, and test-control rules live in `tca-contract.md`.

## Coordinator placement

- If a type mainly renders or manages local UI state, keep it in `Ui/`.
- If a type orchestrates AppKit/QuickLook delegates, listeners, or lifecycle callbacks and routes them into TCA, prefer `Lib/*Coordinator.swift`.

## Package modularization direction

- Treat the current folder structure as a proto-module boundary even before extraction.
- New code should preserve clean layer and slice boundaries so it can move into a Swift Package target later without import or ownership churn.
- Prefer narrow downward dependencies, client-backed external boundaries, and parent-owned orchestration because these survive package extraction best.
- Avoid same-layer cross-slice references and convenience initializers that pull upper-layer feature types downward; these are package-extraction hazards.

## Current partial modularization

- A local Swift Package already exists at `apps/macos/Voyager/Packages/VoyagerModules/Package.swift`.
- Current extracted products include:
  - `VoyagerShared`
  - `VoyagerEntitiesSettings`
  - `VoyagerFeaturesBetaAccess`
  - `VoyagerPagesOnboarding`
  - `VoyagerPagesSettings`
- Treat these extracted targets as proof that App/Pages/Features/Entities/Shared slices are expected to become package-friendly over time.

## Extraction-ready review checks

- Would this slice still compile if moved behind its own package target?
- Are imports pointing only downward or into shared abstractions?
- Is orchestration staying at the parent layer instead of leaking into lower slices?
- Are system and process boundaries isolated behind clients so the slice can be tested out-of-package?
- Is this code depending on project-local convenience rather than a stable layer contract?

## Review checklist

- Is this file in the right layer and segment?
- Is orchestration staying in `Reducer/` or leaking into `Ui/`/`Lib/`?
- Is a new external boundary hidden behind an `Api/*Client.swift`?
- Does the dependency direction still point downward?
- Is this a Voyager-local heuristic that should stay in skill references, or a stable invariant that belongs in `.agents/rules/**`?
