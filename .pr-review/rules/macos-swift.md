# Voyager macOS — SwiftUI + TCA + FSD Review Rules

This file contains path-scoped review instructions for `apps/macos/**/*.swift`.

You are reviewing Voyager macOS as a repository-aware senior engineer.

## Review priority

Prioritize these checks over generic bug finding:

1. Does this change belong in this layer, slice, segment, reducer, view, service, or coordinator?
2. Is there already an existing module, dependency client, helper, model, reducer, or utility that should be reused?
3. Is the PR introducing a duplicate or near-duplicate abstraction?
4. Is responsibility split across multiple owners when one canonical owner should exist?
5. Does the change preserve FSD dependency direction and TCA ownership boundaries?
6. Are lifecycle, cancellation, teardown, rollback, and late-event paths handled by the correct owner?
7. Does the implementation follow the established repository pattern in intent, not just in syntax?

## Canonical architecture references and minimum review gates

Load these repository-root paths for the complete contracts:

- `.agents/skills/voyager-dev/reviewer/review/references/layer-and-segment-rules.md`
- `.agents/skills/voyager-dev/reviewer/review/references/public-boundary-spec.md`
- `.agents/skills/voyager-dev/reviewer/review/references/decision-matrix.md`
- `.agents/skills/voyager-dev/reviewer/review/references/architecture-gate-spec.md`
- `.agents/skills/voyager-dev/planner/reuse-evaluation/references/reuse-discovery-spec.md`

These references own the detailed FSD, segment, public-boundary, reuse-scoring,
and AppKit/system architecture prose. If a reference cannot load, retain these
standalone strict checks rather than treating the review rule as links-only:

- Flag a lower FSD layer importing a higher layer: `Entities` -> `Features`,
  `Pages`, or `App`; `Features` -> `Pages`; or `Shared` -> any higher layer.
  Flag same-layer slice coupling without an explicit narrow boundary.
- Flag a new client, model, helper, view model, or wrapper that duplicates an
  identified existing path/type, bypasses an existing dependency client, or has
  no independent translation, migration, or protection responsibility. Cite the
  existing path/type; do not speculate about reuse.
- Flag package/app reverse dependencies, imports of peer-slice internals, and
  unjustified public-surface expansion without a cross-package consumer. Do not
  flag compiler-required visibility for a public enum associated value or a
  public-class protocol witness.
- Flag UI adapters that call network, filesystem, system SDK, persistence, or
  long-lived observation work directly. Flag AppKit callbacks/coordinators that
  mutate feature state, own service work, or compete with reducer-owned cleanup
  instead of translating physical state into semantic actions.

## Cross-feature command routing

Cross-feature and window-level commands should move through actions, delegate events, or explicit handlers.

Prefer:

- View sends a semantic action.
- Child feature emits a delegate action.
- Parent/page/window reducer routes the command.
- App/window manager dispatches to the focused window through explicit action paths.

Flag:

- Direct mutation of another feature's state.
- View-to-view communication for domain behavior.
- Global notification or singleton routing when a reducer action path exists.
- Command handling duplicated across menu, toolbar, keyboard shortcut, and window manager paths.

## AppKit coordinator review

Use the AppKit/system boundary in
`.agents/skills/voyager-dev/reviewer/review/references/architecture-gate-spec.md`
for the detailed physical-state contract. Independently verify that a coordinator
confirms physical mount/operation success before reporting it as reducer state,
and that close/unmount cancels pending setup so a late event cannot recreate a
physically missing feature.

## Async lifecycle and cancellation

For async effects, streaming, session restore, provider loading, filesystem reads, and callback-driven flows, check:

- Is there a cancellation ID?
- Does close/reset/teardown cancel in-flight work?
- Can a late event reopen or mutate a closed feature?
- Is the resolved context captured once and preserved across the async chain?
- Are failure and rollback paths handled by the canonical owner?
- Are corrupted or missing persisted records handled explicitly?
- If an effect mutates external/system state, can `onAppear`, retry, or a late
  completion overwrite the mutation phase or clear the visible error too early?

Flag late-event bugs and split cleanup ownership aggressively when concrete.

When a PR mutates external system state such as Launch Services, defaults,
file associations, helper registration, or process-global settings, check for
partial-application safety:

- Existing state is read from the same boundary that writes it.
- Read failures stop durable mutation instead of becoming stored fallback values.
- Multi-step mutations either rollback earlier steps on later failure or surface
  the partial state as an explicit error.
- Tests cover failure between steps, rollback, and stale/late diagnostics.

## File-backed storage and credentials

When a PR touches credential, OAuth, provider, settings, or file-backed storage paths:

- Use atomic replacement writes.
- Use file locks when concurrent access is possible.
- Use restrictive file permissions for sensitive files.
- Quarantine corrupted files instead of silently discarding or overwriting them.
- Do not store secrets in UserDefaults, plist, or plain text project files.

Flag storage path mismatches as correctness/data-loss risks, not style issues.

## Environment, secrets, and build settings

When a PR touches `APP_ENV`, `PUBLIC_*` values, `.env.prod`, scheme environment,
`Info.plist`, entitlement files, or env-copy/build scripts, check for runtime
mismatch and secret exposure:

- Secrets must not be committed, copied into bundles, logged, or represented as `PUBLIC_*` values.
- Debug/release environment selection must stay deterministic and match the app/helper/XPC launch path.
- Build scripts must copy only intended secret-free production templates and must not make local `.env.dev` values part of the app bundle.
- `Info.plist`, entitlements, and scheme changes must not silently weaken sandboxing, helper lookup, network access, or release behavior.

Treat concrete leaked secrets and boot/runtime environment mismatches according to
the severity policy in `.pr-review/config.yaml`.

## Helper and XPC contracts

When a PR changes helper launch code, XPC protocols/transports, helper state
broadcasting, indexing, external file replay, or app-helper handoff paths,
review the contract across all participating targets:

- Shared protocol changes must be reflected in the app, helper/XPC service, transport adapters, and tests/fixtures.
- Timeouts, process termination, unavailable helper states, and replay/restore paths must fail closed and surface semantic reducer actions.
- Do not bypass the shared XPC/helper contract with global notifications, singleton state, direct file mutation, or app-only assumptions.
- The app and helper must agree on storage paths, environment, protocol version, and failure semantics.

Flag mismatched contracts, missing failure paths, and one-sided app/helper updates
as concrete runtime risks.

## Package and public boundaries

Use `.agents/skills/voyager-dev/reviewer/review/references/public-boundary-spec.md`
for the detailed public-boundary contract and
`.agents/skills/voyager-dev/reviewer/review/references/layer-and-segment-rules.md`
for package placement. Retain the strict checks above for package reverse
dependencies, peer internals, unjustified public expansion, and wrapper-only
compatibility types. Also flag package tests that rely on `@testable import Voyager`
or app-only fixtures instead of an independent package consumer boundary.

## Test review

Tests should verify architecture-relevant behavior, not just happy paths.

For TCA tests, check:

- Effects are cancellable where needed.
- Delegate actions and parent routing are covered.
- Failure, cancel, restore, teardown, and late-event paths are covered.
- Mutation phases are protected from `onAppear`, retry, and stale completion
  events that could re-enable controls or erase an error banner early.
- Tests model external coordinator/system state explicitly when runtime code receives it from AppKit or system callbacks.
- Test support helpers reuse existing fixtures instead of creating parallel fixture formats.
- New or renamed test files under `Tests/.../Specs/` follow the spec-based naming convention `<SpecID><PascalCaseSpecTitle>Tests.swift`.

Do not ask for tests generically. Name the missing behavior and why it matters.
