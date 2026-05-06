# Voyager Dev Package Extraction Posture

Use this reference when deciding whether a slice boundary is strong enough to survive future package extraction.

## Package modularization direction

- Treat the current folder structure as a proto-module boundary even before extraction.
- New code should preserve clean layer and slice boundaries so it can move into a Swift Package target later without import or ownership churn.
- Prefer narrow downward dependencies, client-backed external boundaries, and parent-owned orchestration because these survive package extraction best.
- Avoid same-layer cross-slice references and convenience initializers that pull upper-layer feature types downward; these are package-extraction hazards.

## Current partial modularization

- Local Swift Packages live under `apps/macos/Packages/**/Package.swift`.
- Current extracted products include:
    - `VoyagerShared`
    - `VoyagerEntitiesAi`
    - `VoyagerEntitiesAppPreferences`
    - `VoyagerEntitiesEntry`
    - `VoyagerFeaturesBetaAccess`
    - `VoyagerFeaturesEntryOperations`
    - `VoyagerPagesOnboarding`
    - `VoyagerPagesSettings`
- Treat these extracted targets as proof that App/Pages/Features/Entities/Shared slices are expected to become package-friendly over time.

## Extraction-ready review checks

- Would this slice still compile if moved behind its own package target?
- Are imports pointing only downward or into shared abstractions?
- Is orchestration staying at the parent layer instead of leaking into lower slices?
- Are system and process boundaries isolated behind clients so the slice can be tested out-of-package?
- Is this code depending on project-local convenience rather than a stable layer contract?

## When to load this file

- New reusable slice or shared module scaffolding
- Reuse decisions that may create a new cross-slice boundary
- Refactors that are meant to prepare code for package extraction
