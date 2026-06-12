---
description: "macOS SwiftUI + TCA structure and dependency rules."
globs: "apps/macos/**/*.swift"
---

# macOS Rules

## Must

- Follow FSD dependency direction:
    - `App (01_App) -> Pages (02_Pages) -> (Widgets (03_Widgets) | Features (Packages/04_Features/*) | Entities (Packages/05_Entities/*) | Shared (Packages/06_Shared/*))`
    - `Widgets (03_Widgets) -> (Features | Entities | Shared)`
    - `Features (Packages/04_Features/*) -> (Features (sibling) | Entities | Shared)`
    - Feature-to-feature (sibling) dependencies are allowed but must be declared in Package.swift and justified (e.g., shared UI components, shared state models).
    - `Entities (Packages/05_Entities/*) -> Shared (Packages/06_Shared/*)`
- Before adding a feature-to-feature dependency, verify no shared entity or shared utility promotion would eliminate the coupling.
- Keep TCA dependencies injected (`@Dependency`) and testable.
- Keep reducers focused (`@Reducer`, effect routing in reducer, no side effects in views).
- Keep each cross-layer concern owned by one canonical type or module.
- Keep user-facing messages and presentation copy in feature/model-owned state, not low-level API/status clients.
- Keep shared visual metadata such as icons or labels behind a single helper or registry.
- Route cross-feature or window-level commands through actions, delegate events, or dedicated handlers.
- Follow `.agents/rules/30-macos/02-tca-observation-lifecycle.md` when moving external/system observation out of SwiftUI views.
- Follow `.agents/rules/30-macos/03-voyager-app-workflow.md` for non-trivial Voyager app, package, host, helper, XPC, or macOS test work.
- Follow `.agents/rules/30-macos/04-xcode-test-plan-visibility.md` when verification depends on SPM package test targets or Xcode schemes.
- Follow `.agents/rules/30-macos/05-swift-testing-gotchas.md` when writing or fixing Swift tests.
- Follow `.agents/rules/30-macos/06-file-backed-storage-invariants.md` when changing credential, OAuth, provider snapshot, settings, or other file-backed storage.
- Follow `.agents/rules/30-macos/08-build-and-verify-tooling.md` when building or testing macOS targets — XcodeBuildMCP mandatory, no fallback.
- Follow `.agents/rules/30-macos/09-entry-fixture-source.md` when writing tests that manipulate entries, entry collections, or entry paths.
- In multi-stage UI callback flows, keep state cleanup, resolved context, and visual ownership with one canonical owner instead of splitting them across success handlers, session-end hooks, and reload paths.
- For scaffold/orchestrator-style TCA work, load the `voyager-dev` orchestrator entry:
    - `.agents/skills/voyager-dev/orchestrator/SKILL.md`
- For code navigation, search, build, and diagnostics, load skill `code-tooling`:
    - `.agents/skills/code-tooling/SKILL.md`

## Must not

- Introduce reverse dependencies (e.g., `Entities` importing `Features/Pages`).
- Call network/filesystem/system SDK directly from SwiftUI views.
- Use global singletons when a dependency client can be injected.
- Maintain parallel canonical types or aliases for the same concept across layers.
- Put presentation copy or UI-facing policy in API clients or raw status wrappers.
- Duplicate shared icon/label mapping logic across views or reducers when a common helper can own it.
- Bypass reducer or action boundaries with direct cross-feature state mutation.

## Execution steps

1. Identify the owning layer before editing state, copy, shared visual metadata, or command routing.
2. Reuse existing dependency clients, reducers, and shared helpers instead of introducing parallel abstractions.
3. Keep views focused on rendering and action sending; move ownership and orchestration decisions into reducers or model-owned helpers.
4. Apply the path-specific Voyager workflow when the change is inside Voyager app/package/host/helper/XPC/test paths.
5. Add the test-plan, Swift-testing, storage invariant, or entry fixture source rules when the change touches those concerns.

## Verification

- Confirm the changed code still follows FSD dependency direction and does not add reverse imports.
- Confirm feature-to-feature dependencies in Package.swift files are justified and not bypassable via entity/shared promotion.
- Confirm system or service access remains behind dependencies/reducers rather than SwiftUI views.
- Confirm each touched concept has one canonical owner after the change.
- Confirm cross-feature or window-level commands are routed through actions, delegate events, or dedicated handlers.
- Confirm this rule file does not contain issue-specific type names, file-path ownership maps, or temporary migration directives.
