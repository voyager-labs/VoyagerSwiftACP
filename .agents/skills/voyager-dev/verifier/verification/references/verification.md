# Voyager Dev Verification

## Task-shape expectations

- `scaffold`
    - Verify the new files land in the correct FSD layer.
    - Verify `State`, `Action`, and reducer entry points match the selected module shape.
- `decompose`
    - Verify ownership boundaries are clearer after the split.
    - Verify moved logic still routes through the parent feature and preserves cancellation ownership.
- `observation-refactor`
    - Verify target views no longer own external/system observation.
    - Verify reducers own `startObserving...` / `stopObserving...` lifecycle plus `.cancellable` / `.cancel`.
    - Verify a semantic internal action receives the routed signal.
- `reuse-guard`
    - Verify the chosen abstraction reuse decision is recorded and that duplicate structures were avoided.
- `package-integration`
    - Load `package-integration-verification.md` when a local SwiftPM package is created, deleted, segmented, or has product/target/dependency/consumer wiring changed.
    - Treat package-local build/test as a first pass; consumer-boundary verification is required when app, host, test, or other package consumers can observe the change.
- `swift6-package`
    - Load `swift6-package-rules.md` when creating packages, adding or moving types into packages, editing Package.swift, or fixing Sendable/concurrency errors.
    - Every new package uses `swift-tools-version:6.0`. Every type in a package is `Sendable` or explicitly annotated.
    - Build the package directly (`swift build --package-path`) after type changes — the app target runs in Swift 5 mode and will not catch strict concurrency errors.

## Preferred execution surface

- For Xcode project listing, build, and test execution, load `xcodebuildmcp-workflow.md` and prefer XcodeBuildMCP tools over raw `xcodebuild` when the MCP server is available.
- If XcodeBuildMCP is not available yet, guide the user through its installation/configuration first.

## Focused verification (preferred first)

```bash
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj -only-testing:VoyagerTests/<TargetTests>
```

For callback-heavy or lifecycle-heavy work, prefer focused suites that prove both boundary behavior and downstream execution-chain behavior before expanding outward.

For multi-step async flows, focused verification must cover cancellation, superseded requests, and stale completions when those outcomes could otherwise write durable state or trigger persistence.

For Swift SPM packages, use: `xcrun swift test --package-path <path> --filter 'Pattern1|Pattern2'`. Split evidence by test class. See `../../../../../rules/30-macos/04-xcode-test-plan-visibility.md` for package test visibility.

For local package graph, product, target, dependency, or consumer wiring changes, also apply `package-integration-verification.md`; standalone `swift build` / `swift test` evidence is not enough when Xcode targets or downstream packages consume the product.

## Full verification

```bash
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj
```

## Optional pre-check

```bash
xcodebuild -list -project apps/macos/Voyager/Voyager.xcodeproj
```

Use focused tests first, then expand to full suite when changing shared reducers or cross-feature dependencies.

If the exact focused target is unclear but the work stays inside Voyager unit tests, prefer this intermediate fallback before the full suite:

```bash
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj -only-testing:VoyagerTests
```

## Formatting and lint

Run formatting/lint whenever touched files include `apps/macos/**/*.swift`.

```bash
mise exec -- swiftlint --config apps/macos/.swiftlint.yml --reporter xcode apps/macos
mise exec -- swiftformat --config apps/macos/.swiftformat apps/macos --verbose
```

Prefer running formatting/lint before the final test pass so style-only churn does not hide functional failures.

## Search-based checks

- Use `grep` or `ast-grep` when architecture changes need a mechanical proof point.
- For observation refactors, search the touched `Ui/*.swift` files for `.onReceive(` and `NotificationCenter.default.publisher`.
- For decomposition or model splits, search for stale type names, dead extension files, or bypassed reducer routes.
- For callback-heavy flows, search for duplicate cleanup ownership, weak-context re-derivation, and missing fallback paths where framework callbacks can lose detail.
- For multi-step async flows, search for durable writes or persistence calls that can execute after cancellation, supersession, or failed verification.
- When tests reveal spec/implementation mismatches, document gaps in `.sisyphus/evidence/{plan_slug}/` files with source, spec reference, current behavior, and rationale for deferral. Confirm zero canonical spec changes needed.

## Skill integrity checks

When a task updates verifier skills, references, or evals under `.agents/skills/**`, verify the integrity:

- Eval validity: parse every touched `evals.json` with `python3 -m json.tool`.
- Scope guardrail: confirm `.agents/rules/**` did not change unless the plan explicitly authorized a rule update.
- Evidence: record the JSON parse result and any missing eval runner discovery in `.sisyphus/evidence/`.

## Layer checks

- Load `../../../reviewer/boundary/references/layer-and-segment-rules.md` only when layer choice, segment placement, or dependency direction changed.
- Apply the layer-specific review checklist from `../../../reviewer/boundary/references/layer-and-segment-rules.md` once one of those conditions is true.
- Load `../../../planner/scaffold/references/package-extraction-posture.md` only when the task changes package-facing boundaries or extraction readiness.
- When needed, use search-based proof for known failure modes such as widget-owned `Api/`, reverse imports, or page-specific logic leaking downward.

## FSD checks

- Apply `../../../reviewer/boundary/references/layer-and-segment-rules.md` and `../../../reviewer/boundary/references/public-boundary-spec.md` only when layer choice, slice boundary, or segment naming changed.

## Boundary and test checks

- When slice-boundary changes are involved, load and apply `../../../reviewer/boundary/references/public-boundary-spec.md` checks.
- When reducer or integration tests change, load and apply `../../testing/references/testing-playbook.md` checks.
- When coordinator or adapter code changes, verify at least one focused test covers the real callback → reducer → effect chain instead of routing-only interception.
- When semantics depend on branch kind or lifecycle outcome, verify the distinct success, failure, cancel, reload, and teardown paths separately.
- When persistence follows verification or another async precondition, verify that failure, cancellation, and superseded completions do not commit success state.

## Split-target spec verification

When a spec spans two test targets (app and package), apply these additional gates:

- Confirm both targets have a suite with the same spec ID and consistent `// MARK:` / traceability comment structure.
- Confirm each suite only asserts behavior within its own target ownership scope.
- Run focused tests per target (see `../../testing/references/testing-playbook.md` for filter commands). Report pass/fail per target, not merged.
- Verify no support files cross target boundaries (no symlinks, no shared file paths between targets).

## Few-shot examples

- **Bad:** Verification stops after a routing assertion because the callback reached the reducer boundary.
  **Good:** Continue until at least one focused test proves the downstream reducer/effect behavior too.

- **Bad:** Verification treats all lifecycle outcomes as equivalent because the same callback family handled them.
  **Good:** Verify the distinct branch outcomes separately when success, failure, cancel, reload, or teardown are supposed to behave differently.
