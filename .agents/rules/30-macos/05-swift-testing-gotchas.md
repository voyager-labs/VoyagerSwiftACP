---
alwaysApply: true
description: "Swift testing gotchas for Voyager macOS test code."
---

# Swift Testing Gotchas

## Applies when

- Writing Swift test assertions under `apps/macos/**`.
- Using XCTest or Swift Testing with enums that have a `.none` case.
- Attempting to use `Set<T>` for exhaustive distinctness proofs.

## Must

- Use fully-qualified enum names in assertions when an enum has a `.none` case (e.g., `ProviderStatusReason.none` instead of `.none`). Swift resolves `.none` to `Optional.none` in optional contexts.
- Use pairwise `XCTAssertNotEqual` loops for exhaustive distinctness proofs when a type is `Equatable` but not `Hashable`. `Set<T>` is unavailable for non-Hashable types.

## Must not

- Do not use bare `.none` in test assertions when the type is optional-compatible and has a `.none` case — it will resolve to `Optional.none`.
- Do not attempt `Set<T>` when `T` is not `Hashable`.

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
