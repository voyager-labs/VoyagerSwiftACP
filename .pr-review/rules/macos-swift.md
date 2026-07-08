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

## FSD architecture model

Layer direction (top-to-bottom only):

```text
01_App -> 02_Pages -> 03_Widgets -> 04_Features -> 05_Entities -> 06_Shared
```

- `01_App` may orchestrate global app lifecycle, commands, menu state, and window management.
- `02_Pages` may assemble lower layers for a page-level experience.
- `03_Widgets` may provide reusable page sections, usually UI-oriented and injected from above.
- `04_Features` owns use-case logic and reusable feature flows.
- `05_Entities` owns domain concepts such as Entry or Collection.
- `06_Shared` owns globally reusable clients, config, utilities, design tokens, and common models.

Flag these patterns:

- `Entities` importing or depending on `Features`, `Pages`, or `App`.
- `Features` depending on `Pages` or page-specific UI containers.
- Same-layer slices directly depending on each other when the shared concept should move lower.
- `Shared` depending on any higher layer.
- App/Page layers accumulating domain logic that belongs in a Feature, Entity, or Shared client.

## TCA and segment ownership

Use these segment responsibilities:

- `Ui/`: SwiftUI views and view adapters. Views should render state and send actions.
- `Reducer/`: TCA reducer orchestration, child reducer composition, effect routing, cancellation IDs.
- `Model/`: state, actions, domain/display models, value types.
- `Api/`: dependency clients, live/test values, external service boundaries.
- `Lib/`: helpers, coordinators, delegates, adapters, AppKit/system integration glue.
- `Config/`: constants, design tokens, configuration.

Flag changes where:

- A SwiftUI view performs network, filesystem, system SDK, persistence, or long-lived observation work.
- A reducer directly constructs external services instead of using dependency clients.
- A dependency client owns UI policy or presentation copy.
- A coordinator starts owning domain decisions that should be reducer state.
- A model/helper is placed in `Shared` even though it is page-specific.
- State or action types are split in a way that hides ownership rather than clarifying it.

## Reuse and duplicate detection

Before accepting any new abstraction, search mentally through the existing codebase patterns and ask:

- Is there already a dependency client for this external capability?
- Is there already a reducer/helper/adapter for this command or lifecycle?
- Is there already an entity model or display model that represents this concept?
- Is this new type a compatibility wrapper that could be removed by extending the canonical type?
- Is this new utility duplicating a mapping, label, icon, provider, status, or formatting helper?

Flag high-confidence duplication when:

- Two types represent the same domain concept with different names.
- Two helpers perform the same mapping across layers.
- A new service bypasses an existing dependency client.
- A new view model duplicates an existing display model.
- A new compatibility wrapper exists only because the new code did not adapt the existing owner.

Do not flag reuse speculatively. Cite the existing path/type/pattern that should be reused.

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

For AppKit and SwiftUI coordinator code, verify the distinction between logical reducer intent and physical AppKit state.

Physical state includes:

- `NSSplitView` arranged subviews
- actual view hierarchy membership
- visible frame width/height
- first responder/focus state
- window lifecycle
- delegate callbacks
- mounted/teardown state

Flag issues where:

- The reducer assumes an AppKit view is physically mounted before the coordinator confirms it.
- Menu or toolbar state derives from logical intent when the user-visible state depends on physical mount.
- A coordinator mutates reducer state before the AppKit operation actually succeeds.
- A close/unmount path does not cancel pending open/setup effects.
- Retry logic can get stuck in a logical-open / physically-missing state.

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
- Required app/web/checkout/pricing/support URLs must use canonical env keys or explicit error handling; placeholder fallbacks such as `example.invalid`, localhost defaults, empty strings, or made-up base URLs are concrete runtime mismatches.

Treat leaked secrets as P0 and boot/runtime environment mismatches as P1 when the failure is concrete.

## Helper and XPC contracts

When a PR changes helper launch code, XPC protocols/transports, helper state
broadcasting, indexing, external file replay, or app-helper handoff paths,
review the contract across all participating targets:

- Shared protocol changes must be reflected in the app, helper/XPC service, transport adapters, and tests/fixtures.
- Timeouts, process termination, unavailable helper states, and replay/restore paths must fail closed and surface semantic reducer actions.
- Do not bypass the shared XPC/helper contract with global notifications, singleton state, direct file mutation, or app-only assumptions.
- The app and helper must agree on storage paths, environment, protocol version, and failure semantics.

Flag mismatched contracts, missing failure paths, and one-sided app/helper updates as P1 runtime risks.

## Package and public boundaries

When a PR touches Swift packages or promotes code across package boundaries:

- Package targets must not import the app target or higher FSD layers; use dependency injection, adapters, or lower-layer promotion instead.
- Avoid `@testable import Voyager` or app-only fixtures in package tests.
- Public API promotions must expose the initializer, stored properties, enum cases, and dependency surfaces needed by real consumers.
- Wrapper-only compatibility types should be removed or folded into the canonical owner unless they represent a stable external boundary.

Flag package reverse dependencies, incomplete public surfaces, and compatibility wrappers that hide ownership drift as P1 maintainability risks.

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
