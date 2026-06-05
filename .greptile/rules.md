# Voyager PR Review Rules

This file is the source of truth for Voyager AI-powered PR review policy. `AGENTS.md` files should point here instead of duplicating review language, severity, noise, architecture, or reuse rules.

You are reviewing Voyager as a repository-aware senior engineer.

The purpose of this review is not to act as a linter, formatter, or CI substitute. The primary goal is to determine whether the PR fits Voyager's existing architecture, ownership model, module boundaries, and reuse patterns.

## PR auto-review exclusions

Greptile should not automatically review PRs that are operationally known to add review noise rather than new implementation risk.

Configured skip paths in `.greptile/config.json`:

- Branch filters: exclude revert branches such as `revert-*`, `*revert-*`, `revert/**`, `**/revert-*`, `**/*revert-*`, and `**/revert/**`.
- Labels: skip PRs labeled `skip-greptile`, `no-greptile`, `duplicate-diff`, or `duplicate-pr`.
- Keywords: skip PRs whose title/description/last commit message contains the narrow automatic-revert marker `This reverts commit`, or explicit operational markers `skip-greptile`, `no-greptile`, `duplicate-diff`, or `duplicate-pr`. Do not use broad standalone words such as `Revert` as skip keywords.

Duplicate-diff PRs are not automatically detectable from Greptile configuration alone. Mark intentionally re-uploaded equivalent diffs with one of the configured labels or keywords so Greptile skips automatic review.

## Output language

- Write all review comments, summaries, and explanations in Korean.
- Keep code symbols, file paths, type names, API names, and commands in English.
- Do not write generic English review comments.

## Review severity and noise policy

Only leave comments for P0/P1-level issues:

- P0: blocker, data loss, security issue, crash, or severe architectural breakage.
- P1: high-confidence correctness, lifecycle, ownership, boundary, or maintainability risk.

Do not comment on:

- Formatting
- Import ordering
- Naming nits
- Minor style preferences
- Obvious type errors
- Build failures that CI would immediately catch
- Test failures that CI would immediately surface
- Low-confidence speculation
- Generic “consider refactoring” suggestions without concrete evidence

When multiple symptoms share one root cause, leave one consolidated comment at the strongest representative location.

Every comment must explain:

1. What is wrong.
2. Why it matters in this repository.
3. Which existing pattern/module/type should be reused or extended.
4. What concrete alternative would fit the codebase better.

## Repository-aware review priority

Prioritize these checks over generic bug finding:

1. Does this change belong in this layer, slice, segment, reducer, view, service, or coordinator?
2. Is there already an existing module, dependency client, helper, model, reducer, or utility that should be reused?
3. Is the PR introducing a duplicate or near-duplicate abstraction?
4. Is responsibility split across multiple owners when one canonical owner should exist?
5. Does the change preserve FSD dependency direction and TCA ownership boundaries?
6. Are lifecycle, cancellation, teardown, rollback, and late-event paths handled by the correct owner?
7. Does the implementation follow the established repository pattern in intent, not just in syntax?

## Voyager architecture model

Voyager macOS uses SwiftUI + TCA with FSD-style layering.

Layer direction:

```text
01_App -> 02_Pages -> 03_Widgets -> 04_Features -> 05_Entities -> 06_Shared
```

Allowed dependency direction is top-to-bottom only.

Examples:

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

For AppKit and SwiftUI coordinator code, verify the distinction between:

- logical reducer intent, and
- physical AppKit state.

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

Flag late-event bugs and split cleanup ownership aggressively when concrete.

## File-backed storage and credentials

When a PR touches credential, OAuth, provider, settings, or file-backed storage paths:

- Use atomic replacement writes.
- Use file locks when concurrent access is possible.
- Use restrictive file permissions for sensitive files.
- Quarantine corrupted files instead of silently discarding or overwriting them.
- Do not store secrets in UserDefaults, plist, or plain text project files.

Flag storage path mismatches as correctness/data-loss risks, not style issues.

## Backend API contracts

When a PR touches backend routes, request/response schemas, search conversion,
or API clients, verify the observable contract rather than implementation style:

- Response envelopes, status codes, and error shapes remain compatible with
  existing clients.
- Internal exceptions, tracebacks, filesystem paths, and provider details are
  not exposed as raw API responses.
- Search conversion endpoints preserve the documented convert-only contract;
  do not introduce implicit indexing, filesystem mutation, or app-runtime
  coupling through backend APIs.
- Schema/model changes include matching route behavior and tests for success,
  validation failure, and provider/backend failure paths.

Flag API contract drift as a correctness or compatibility risk, not a naming
or formatting issue.

## Environment, secrets, and build settings

When a PR touches `APP_ENV`, `PUBLIC_*` values, `.env.prod`, scheme
environment, `Info.plist`, entitlement files, or env-copy/build scripts, check
for runtime mismatch and secret exposure:

- Secrets must not be committed, copied into bundles, logged, or represented as
  `PUBLIC_*` values.
- Debug/release environment selection must stay deterministic and match the
  app/helper/XPC launch path.
- Build scripts must copy only intended secret-free production templates and
  must not make local `.env.dev` values part of the app bundle.
- `Info.plist`, entitlements, and scheme changes must not silently weaken
  sandboxing, helper lookup, network access, or release behavior.

Treat leaked secrets as P0 and boot/runtime environment mismatches as P1 when
the failure is concrete.

## Helper and XPC contracts

When a PR changes helper launch code, XPC protocols/transports, helper state
broadcasting, indexing, external file replay, or app-helper handoff paths,
review the contract across all participating targets:

- Shared protocol changes must be reflected in the app, helper/XPC service,
  transport adapters, and tests/fixtures that exercise the contract.
- Timeouts, process termination, unavailable helper states, and replay/restore
  paths must fail closed and surface semantic reducer actions.
- Do not bypass the shared XPC/helper contract with global notifications,
  singleton state, direct file mutation, or app-only assumptions.
- The app and helper must agree on storage paths, environment, protocol version,
  and failure semantics.

Flag mismatched contracts, missing failure paths, and one-sided app/helper
updates as P1 runtime risks.

## Package and public boundaries

When a PR touches Swift packages or promotes code across package boundaries,
verify package independence and public API completeness:

- Package targets must not import the app target or higher FSD layers; use
  dependency injection, adapters, or lower-layer promotion instead.
- Avoid `@testable import Voyager` or app-only fixtures in package tests.
- Public API promotions must expose the initializer, stored properties, enum
  cases, and dependency surfaces needed by real consumers, not only the current
  call site.
- Wrapper-only compatibility types should be removed or folded into the
  canonical owner unless they represent a stable external boundary.

Flag package reverse dependencies, incomplete public surfaces, and compatibility
wrappers that hide ownership drift as P1 maintainability risks.

## Local-only artifacts

The following paths are local agent/runtime artifacts:

- `.omx/**`
- `.sisyphus/**`

They must not be tracked, staged, committed, or included in PRs.

If these appear in a PR, leave a high-severity repository hygiene comment.

## Test review

Tests should verify architecture-relevant behavior, not just happy paths.

For TCA tests, check:

- Effects are cancellable where needed.
- Delegate actions and parent routing are covered.
- Failure, cancel, restore, teardown, and late-event paths are covered.
- Tests model external coordinator/system state explicitly when runtime code receives it from AppKit or system callbacks.
- Test support helpers reuse existing fixtures instead of creating parallel fixture formats.

Do not ask for tests generically. Name the missing behavior and why it matters.

## Comment format

Use this format for findings:

```markdown
[P1] <short Korean finding title>

<왜 문제가 되는지 한국어로 설명. 이 레포의 구조/소유권/재사용 관점에서 구체적으로 설명.>

Evidence:

- `<path>`: <relevant symbol or behavior>
- Existing pattern to reuse: `<path or type>`

Suggested direction:

- <concrete alternative>
```

If there are no P0/P1 findings, say that no high-confidence structural/runtime issues were found.

## Review output and decision

When a review is not skipped, structure the final output around:

- TL;DR: Korean summary of intent, scope, and verdict.
- Findings: P0/P1 findings only, using the comment format above. If there are no findings, state that no high-confidence structural/runtime issues were found.
- Coverage: required for large PRs or partial reviews; state reviewed/skipped areas and confidence.
- Tests/QA: concrete commands or user flows relevant to the reviewed risk.
- Risk: rollback, feature flag, migration, or follow-up risk when applicable.
- Review decision: `approve`, `comment`, or `request changes`.

Decision policy:

- Use `request changes` when there is one or more P0/P1 finding.
- Use `approve` when there are no P0/P1 findings and the change is well-structured.
- Use `comment` when there are no P0/P1 findings but the review should record non-blocking observations or coverage caveats.

Non-blocking observations must not be labeled as P0/P1 findings.
