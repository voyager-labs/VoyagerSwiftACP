---
description: "Design rules for TCA dependency clients: capability boundaries, composition, override safety and macro policy."
globs: "apps/macos/**"
---

# Dependency Client Design

This reference owns client granularity and composition. Placement and effect lifecycle remain in `.agents/skills/voyager-dev/implementer/tca-contract/references/tca-contract.md`.

## Must

- Define a coherent external capability that tests or composition need to replace. Prefer the nearest owning slice's `Api/`; do not add a client for pure sorting, projection, normalization or a one-line delegation.
- Split unrelated capabilities and security/lifetime boundaries. Do not split mechanically per SDK call or public method, and do not require Interface/Live/Testing targets for every package.
- Prefer concrete client structs and manual `DependencyKey` registration, consistent with the existing codebase.
- Register only a real replacement/override boundary. Inspect legitimate consumers, including native adapters and composed clients; "no reducer reads the key directly" alone does not prove a phantom dependency.
- Purely private implementation helpers do not need a `DependencyKey`. A new client must provide translation, isolation, lifecycle or protection value rather than hide a peer/upward dependency.
- Compose via explicit `live(dependency: ...)` factories or resolve `@Dependency` at the execution point where override scope must apply. Test transitive overrides; an eagerly captured `.liveValue` must not bypass them.
- Provide `testValue` and `previewValue`. Unexpected test calls fail loudly; use explicit named fixtures for intended fake behavior, not silent default successes.
- Keep public capability names about what the caller needs, while implementation SDK details stay private where practical.
- Group dependent cross-seam steps under the real workflow owner with immutable input and a coherent cancellation policy. Reducer-private helpers may sequence calls inside one effect without a new orchestration client.

## Must not

- Do not introduce overlapping clients for an existing capability without migrating its owner and consumers together.
- Do not reach directly into `OtherClient.liveValue` from a live operation closure to bypass dependency overrides.
- Do not put hidden authoritative UI State or a second business state machine inside an actor/client to shorten a reducer.
- Do not introduce a client solely to wrap native scroll/bounds notifications. Physical observation can remain in the adapter with explicit cleanup; domain/system observation remains client/reducer-owned.
- Do not add `@DependencyClient` in a single package as incidental refactoring. A macro migration is a deliberate cross-package convention change, not required by this work.
- Do not make internal token-refresh or lifecycle details public unless there is a real external consumer contract.
- Do not treat task cancellation as proof of rollback. External mutations may need partial-result, ambiguity, rollback or read-back contracts.

## Execution steps

1. Name the caller's capability, external boundary, lifetime, mutable authority and failure behavior.
2. Inspect existing clients and consumers before adding a type or registration.
3. Separate UI/domain workflow decisions from external IO implementation and pure policy.
4. Choose factory or execution-time resolution deliberately; record how override inheritance is tested.
5. Capture immutable inputs and Sendable-safe dependencies. Define where results are accepted/rejected by owner identity and phase.
6. Add explicit test/preview implementations and failure-path tests, including transitive override and cancellation after partial external mutation where applicable.
7. Keep client and `DependencyValues` registration discoverable together. Narrow the public surface only after reference/compile evidence.

## Verification

Search/AST can locate `.liveValue`, direct SDK calls, new registrations and missing fixture surfaces. Inspect their actual ownership and execution context before classifying a finding. Run tests that override the lower-level client through the public feature path; a text match alone does not prove eager capture or correct propagation.

Use compiler evidence for Sendable/access constraints, tests for client behavior and composition overrides, and fixtures for externally owned payloads. Do not claim a client graph is correct from naming or from one `@Dependency` reference count.
