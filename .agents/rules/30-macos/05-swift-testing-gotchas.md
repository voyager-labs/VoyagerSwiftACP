---
description: "Swift testing gotchas for Voyager macOS test code."
globs: "apps/macos/**/*.swift"
---

# Swift Testing Gotchas

## Must

- Use fully-qualified enum names in assertions when an enum has a `.none` case (e.g., `ProviderStatusReason.none` instead of `.none`). Swift resolves `.none` to `Optional.none` in optional contexts.
- Use pairwise `XCTAssertNotEqual` loops for exhaustive distinctness proofs when a type is `Equatable` but not `Hashable`. `Set<T>` is unavailable for non-Hashable types.

## Must not

- Do not use bare `.none` in test assertions when the type is optional-compatible and has a `.none` case — it will resolve to `Optional.none`.
- Do not attempt `Set<T>` when `T` is not `Hashable`.
- Do not write tests that read Swift source files to assert literal strings, view type names, or declaration order as behavior proof — they couple tests to source text, not behavior. Verify observable behavior instead: TCA action/state/effect assertions, accessibility, hitTest/drop behavior, dependency-call assertions. Fixture/data-file assertions remain allowed when behavior genuinely depends on fixture content.

## Execution steps

1. Before writing enum assertions, check if the enum has a `.none` case.
2. If yes, use the fully-qualified name (e.g., `EnumName.none`) in all assertions.
3. Before using `Set<T>` for distinctness proofs, verify `T: Hashable`.
4. If `T` is not `Hashable`, use pairwise comparison loops instead:
    ```swift
    let allCases: [MyEnum] = [.caseA, .caseB, .caseC]
    for i in allCases.indices {
        for j in (i + 1)..<allCases.count {
            XCTAssertNotEqual(allCases[i], allCases[j])
        }
    }
    ```

## Verification

- `grep -r '\.none,' apps/macos/Packages/**/Tests/` should use fully-qualified names where applicable.
- No `Set<` usage on types that are not `Hashable`.
