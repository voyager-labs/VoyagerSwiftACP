---
description: "Guardrails for extracting and maintaining feature/entity packages under apps/macos/Packages/."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# Package Extraction Guardrails

## Outcome

- This is the canonical owner for package extraction: packages have no upper-layer reverse imports, expose narrow complete public boundaries, declare direct dependencies, and compile/test independently of the app target.
- Detailed FSD placement and public-boundary guidance remains in the boundary reviewer references; this rule retains the package-specific reverse-import and consumer guardrails.

## Default Actions

1. Audit target files for `01_App`, `02_Pages`, and `03_Widgets` dependencies; classify each as dependency injection, entity/shared promotion, or an upper-layer boundary adapter.
2. Replace required upper-layer values with package-owned mirror value types that retain `rawValue` parity, keeping adapters in the upper layer.
3. Declare explicit TCA ecosystem and other direct dependencies in `Package.swift`; resolve design tokens in package `Config/` only when a shared promotion is not warranted.
4. Apply needed Swift 6 isolation annotations and promote a public API as a complete type-level surface.
5. Verify the package builds and tests without importing the app target.

## Decision Rules

- Use `../../reviewer/review/references/layer-and-segment-rules.md` for layer/segment direction and `../../reviewer/review/references/public-boundary-spec.md` for visibility decisions.
- Delegate logging, analytics, and navigation as `Action.Delegate` intent or dependency-client work; the consuming layer performs the side effect.
- Use `nonisolated(unsafe)`, `@preconcurrency`, or `MainActor.assumeIsolated` only when their safety boundary is established; do not use them to hide an unresolved boundary.

## Stop Conditions

- Do not import upper-layer types, depend directly on the app target, retain app typealiases or `@testable import Voyager` workarounds, or leave a reverse dependency unresolved.
- Do not duplicate large design-token files without a documented preferred resolution or use unsafe concurrency suppressions without a real safety argument.

## Verification

- Confirm package sources contain no `import Voyager` or upper-layer import and package tests contain no `@testable import Voyager`.
- Confirm `Package.swift` declares direct TCA dependencies when used, public surfaces are complete, and independent package compilation/tests succeed.
