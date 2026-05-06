# FSD Package Segmentation Checklist

Use this checklist when implementing or reviewing a SwiftPM package segmentation.

## Before moving files

- [ ] Identify package path and module/target name.
- [ ] List all source files under `Sources/<Module>/`.
- [ ] Identify public declarations and top-level helper functions.
- [ ] Search references before narrowing/deleting symbols.
- [ ] Mark compatibility bridges, persisted schema contracts, and migration surfaces.

## Segment classification

- [ ] `Model/`: state, action, payload, DTO, persisted model, schema/version contract.
- [ ] `Reducer/`: TCA reducer, effect routing, cancellation, child scope wiring.
- [ ] `Api/`: dependency client, system/process/network/persistence/UI boundary adapter.
- [ ] `Lib/`: pure helper, mapper, normalization, hydration, registry, compatibility helper.
- [ ] `Ui/`: package-owned view/rendering code only when the package owns UI.
- [ ] `Config/`: constants/config/design-token-like values.
- [ ] No generic `Types/`, `Utils/`, `Helpers/`, or `Misc/` buckets unless the repo already standardizes on them.

## Move pass

- [ ] Move files without renaming symbols.
- [ ] Avoid `Package.swift` edits unless build output proves source discovery failed.
- [ ] Preserve module/product name unless explicitly changing package boundary.
- [ ] Verify root `Sources/<Module>/` has no unintended flat `.swift` files.

## Cleanup pass

- [ ] Narrow file-local helpers to `private`.
- [ ] Narrow package-local types/functions to `internal`.
- [ ] Delete only zero-symbol or zero-reference files/symbols.
- [ ] Extract direct system/IO/UI boundaries into `Api/*Client.swift` or equivalent.
- [ ] Keep live compatibility bridges and label follow-up cleanup.

## Verification

- [ ] Run package test/build command.
- [ ] Run app/integration build if external consumers changed.
- [ ] Search package for forbidden upper-layer imports.
- [ ] Search reducers for extracted system boundary construction.
- [ ] Document intentionally kept bridges/pass-throughs.

## Generic few-shot segment examples

These examples are intentionally generic. Adapt names to the package domain instead of copying them literally.

### Example 1: Domain package with TCA reducer

| Source file           | Segment    | Why                                       |
| --------------------- | ---------- | ----------------------------------------- |
| `FooState.swift`      | `Model/`   | Package-owned TCA state                   |
| `FooAction.swift`     | `Model/`   | Package-owned TCA action contract         |
| `FooPayloads.swift`   | `Model/`   | Cross-boundary value DTOs                 |
| `FooFeature.swift`    | `Reducer/` | `@Reducer` composition and effect routing |
| `FooClient.swift`     | `Api/`     | Dependency client / external boundary     |
| `FooNormalizer.swift` | `Lib/`     | Pure transformation helper                |

### Example 2: Package with persisted format and compatibility bridges

| Source file                   | Segment  | Why                                                        |
| ----------------------------- | -------- | ---------------------------------------------------------- |
| `FooFile.swift`               | `Model/` | Persisted file-format model and schema fields              |
| `FooFile+Compatibility.swift` | `Lib/`   | Migration/compatibility helpers around the persisted model |
| `FooFileClient.swift`         | `Api/`   | Load/save dependency boundary                              |
| `FooHydration.swift`          | `Lib/`   | Pure conversion from persisted data into runtime shape     |

### Example 3: System UI boundary extraction

| Before                                 | After                                   | Why                                                                |
| -------------------------------------- | --------------------------------------- | ------------------------------------------------------------------ |
| Reducer directly creates `SavePanel()` | `Api/FooSavePanelClient.swift`          | System UI is a testable boundary                                   |
| Reducer receives SDK object            | Reducer receives `URL?` or typed result | Reducer should depend on domain values, not UI objects             |
| Tests open real UI                     | Tests inject deterministic closures     | Tests must cover success/cancel/failure without system interaction |
