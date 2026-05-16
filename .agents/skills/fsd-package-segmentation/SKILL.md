---
name: fsd-package-segmentation
description: Use this when reorganizing an existing SwiftPM package or package-like source target into FSD-style segments such as Model, Lib, Api, Reducer, Ui, and Config. Trigger for package segmentation, package internal seam cleanup, flatten-to-segments refactors, moving files inside Sources/<Module>/, or deciding where package files belong, even when the package is not an Entity package.
compatibility: opencode
metadata:
    area: architecture
    pattern: swiftpm-fsd-package-segmentation
---

# FSD Package Segmentation

Use this skill to turn a flat or weakly organized SwiftPM package source target into explicit FSD-style internal segments while preserving module identity and public behavior.

This skill is package-focused. It complements `voyager-dev`, which handles Voyager app/TCA/FSD workflows. Use both when the package is a Voyager macOS package or the change also touches app/page/feature integration.

## Trigger

- Reorganize `Sources/<Module>/` into `Model/`, `Lib/`, `Api/`, `Reducer/`, `Ui/`, or `Config/`.
- Decide which segment a package file belongs in.
- Extract a package-internal seam, especially a dependency client or system boundary.
- Clean up public/internal access while segmenting a package.
- Prove a package remains isolated from upper layers after file moves.
- Audit compatibility bridges before deleting or narrowing them.

## Core workflow

1. **Baseline before moving.** Inventory every source file and public/cross-boundary symbol.
2. **Classify files by responsibility.** Use the segment responsibilities below; do not classify by filename alone.
3. **Move first, change second.** Prefer a pure file-move pass before semantic cleanup.
4. **Preserve module identity.** If the SwiftPM target/module name stays unchanged, external `import <Module>` statements usually need no edits.
5. **Narrow only with proof.** Use references/search before changing `public` to `internal`/`private` or deleting files.
6. **Extract system boundaries into `Api/`.** Reducers and pure libs should not construct UI panels, filesystem watchers, network clients, clocks, UUID/randomness, or other hard-to-test dependencies directly.
7. **Verify structure and behavior.** Run package tests/builds and static boundary checks after moves and after semantic changes.

## Segment responsibilities

Use the smallest segment set the package actually needs.

- `Model/`
    - State, Action, domain models, DTOs, payloads, persisted file-format models, schema/version contracts.
    - Put public cross-boundary value contracts here when they describe package domain data.
- `Reducer/`
    - TCA reducers, reducer composition, effect routing, cancellation ownership, child reducer wiring.
    - Reducer helper functions that are only called from one reducer file should usually be `private` in that file.
- `Api/`
    - Dependency clients, adapters around system/process/network/persistence/UI boundaries, testable environment seams.
    - Prefer concrete dependency-client structs over protocol-only abstractions when the codebase already uses that pattern.
- `Lib/`
    - Pure helpers, mappers, normalization, hydration, registries, compatibility helpers, coordinators that do not own the primary external boundary.
    - Do not park a primary system boundary here when it should be faked through `Api/`.
- `Ui/`
    - Rendering, lightweight view adapters, package-owned UI surfaces. Omit for non-UI packages.
- `Config/`
    - Static constants, configuration values, design tokens, package metadata that is not domain state.

Avoid generic buckets such as `Types/`, `Utils/`, `Helpers/`, or `Misc/` when a standard segment communicates ownership better.

## Baseline matrix

Before edits, produce or mentally maintain this matrix:

| File | Public/cross-boundary symbols | Current location | Target segment | References | Decision | Rationale |
| ---- | ----------------------------- | ---------------- | -------------- | ---------- | -------- | --------- |

Decision values:

- `move` — file belongs in a segment with no semantic change.
- `keep public` — external references prove it is part of package surface.
- `make internal` — no external references; still package-local.
- `make private` — only used in the same file.
- `remove` — no symbols or zero references with proof.
- `keep bridge` — compatibility/migration surface is still consumed.

## Recommended execution order

### 1. Inventory

- List all `.swift` files under `Sources/<Module>/`.
- Identify public declarations and top-level helpers.
- Find external references outside the package for deletion/narrowing candidates.
- Mark compatibility bridges and persisted schema contracts explicitly.

### 2. Pure segmentation

- Move files into target segment directories.
- Do not rename symbols during the pure move.
- Do not combine files unless the task explicitly requires it.
- For SwiftPM packages, assume recursive source discovery and avoid `Package.swift` edits unless the build proves otherwise.

### 3. Semantic seam cleanup

- Narrow access for symbols proven package-local or file-local.
- Delete only files/symbols with zero-reference proof.
- Extract direct system/UI/IO boundaries into `Api/*Client.swift` or the package's equivalent dependency-client pattern.
- Keep bridges with live references and label follow-up cleanup rather than forcing removal.

### 4. Integration repair

- If the module name stayed stable, first verify whether external imports already compile unchanged.
- Repair only compile-proven breakage or intentional public API changes.
- Keep dependency direction clean: package code must not import upper-layer app/page/feature modules.

### 5. Verification

Run checks appropriate to the package:

- Package test/build command, e.g. `swift test --package-path <package>`.
- App or integration build if consumers changed.
- Static search for forbidden upper-layer imports inside the package.
- Static search that reducers no longer instantiate extracted system boundaries directly.
- Directory check that `Sources/<Module>/` has no unexpected flat `.swift` files.

## Output format for planning or review

When asked to plan or review a segmentation, return:

1. **Segment map** — files grouped by target segment.
2. **Public-surface decisions** — keep/narrow/remove/bridge decisions with proof requirements.
3. **Semantic changes** — seams to extract and access-control changes, separated from pure moves.
4. **Verification plan** — exact tests/builds/static searches.
5. **Follow-ups** — live bridges or ownership questions intentionally deferred.

## Hard guardrails

- Do not delete compatibility or migration bridges without reference proof.
- Do not change persisted schema names or module names as part of a segmentation unless explicitly requested.
- Do not introduce upper-layer imports into lower/package code to fix compile errors.
- Do not hide system boundaries in reducers or pure `Lib/` code when tests need to fake them.
- Do not treat a stable module-name file move as requiring external import churn until a build proves it.

## Bundled references

- `references/checklist.md` — quick checklist for executing or reviewing a segmentation.
