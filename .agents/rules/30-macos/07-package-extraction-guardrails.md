---
description: "Guardrails for extracting and maintaining feature/entity packages under apps/macos/Packages/."
globs: "apps/macos/**/*.swift"
---

# Package Extraction Guardrails

## Must

- Run a reverse-dependency audit before extraction: grep the target files for imports of `01_App`, `02_Pages`, or `03_Widgets` types. Resolve each reverse dependency via DI, protocol abstraction, or entity promotion before proceeding.
- When a feature package needs a type from an upper layer, create a package-owned mirroring value type with rawValue parity and place the adapter function in the upper layer. Do not import upper-layer types into the package.
- Delegate side effects (logging, analytics, navigation) to `Action.Delegate` or a dependency client. The package emits intent; the consuming layer executes.
- Resolve VoyagerDS (design token) dependencies explicitly:
    - If only a few tokens are needed: copy into `Config/` within the package (pragmatic).
    - If tokens are widely shared across packages: promote VoyagerDS to a shared package first.
- Apply Swift 6 concurrency annotations proactively during extraction:
    - `nonisolated(unsafe)` for `PreferenceKey.defaultValue` and similar static defaults.
    - `@preconcurrency` for delegate protocols (e.g., `SPUUpdaterDelegate`).
    - `MainActor.assumeIsolated` for cache client access from `@MainActor`-isolated reducers.
    - Explicit `import` for types used via `MemberImportVisibility` in the app target.
- Declare all TCA ecosystem dependencies (CasePaths, Perception, etc.) explicitly in `Package.swift`. Do not rely on transitive dependency resolution — it causes linker errors in tests.
- Promote public API surface as a complete set: initializers, stored properties, enum cases, and associated types must be promoted together, not individually.

## Must not

- Import `01_App`, `02_Pages`, or `03_Widgets` types from a package under `apps/macos/Packages/`.
- Create a package that depends on the app target directly.
- Leave reverse dependencies unresolved and force the package to compile via workarounds (e.g., `typealias` to app types, `@testable import Voyager` in package tests).
- Duplicate large design-token files without documenting the decision and preferred resolution path.
- Suppress Swift 6 concurrency warnings with `@unchecked Sendable` or `nonisolated(unsafe)` without confirming the value is genuinely safe.

## Execution steps

1. Grep target files for imports of types from upper layers (`01_App`, `02_Pages`, `03_Widgets`).
2. For each reverse dependency: classify as DI-able, promotable, or requiring a boundary adapter.
3. Create mirroring value types for boundary adapters with rawValue parity.
4. Add all explicit dependencies (TCA ecosystem included) to `Package.swift`.
5. Apply Swift 6 concurrency annotations proactively.
6. Promote public API surface as complete type-level units.
7. Verify package compiles independently and tests pass without `@testable import Voyager`.

## Verification

- `grep -r 'import Voyager' apps/macos/Packages/04_Features/*/Sources/` returns no matches (bare app import forbidden).
- `grep -r '@testable import Voyager' apps/macos/Packages/04_Features/*/Tests/` returns no matches.
- Each package `Package.swift` declares CasePaths and Perception explicitly when TCA is used.
- No package source file imports types from `01_App`, `02_Pages`, or `03_Widgets` directly.
