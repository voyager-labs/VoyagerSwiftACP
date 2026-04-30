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

## Preferred execution surface

- For Xcode project listing, build, and test execution, load `xcodebuildmcp-workflow.md` and prefer XcodeBuildMCP tools over raw `xcodebuild` when the MCP server is available.
- If XcodeBuildMCP is not available yet, guide the user through its installation/configuration first.

## Focused verification (preferred first)

```bash
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj -only-testing:VoyagerTests/<TargetTests>
```

For callback-heavy or lifecycle-heavy work, prefer focused suites that prove both boundary behavior and downstream execution-chain behavior before expanding outward.

For Swift SPM packages, use: `xcrun swift test --package-path <path> --filter 'Pattern1|Pattern2'`. Split evidence by test class. See `30-macos/04-xcode-test-plan-visibility.md` for package test visibility.

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

Run formatting/lint whenever touched files include `apps/macos/Voyager/**/*.swift`.

```bash
swiftlint --config apps/macos/Voyager/.swiftlint.yml --reporter xcode
swiftformat --config apps/macos/Voyager/.swiftformat apps/macos/Voyager --verbose
```

Prefer running formatting/lint before the final test pass so style-only churn does not hide functional failures.

## Search-based checks

- Use `grep` or `ast-grep` when architecture changes need a mechanical proof point.
- For observation refactors, search the touched `Ui/*.swift` files for `.onReceive(` and `NotificationCenter.default.publisher`.
- For decomposition or model splits, search for stale type names, dead extension files, or bypassed reducer routes.
- For callback-heavy flows, search for duplicate cleanup ownership, weak-context re-derivation, and missing fallback paths where framework callbacks can lose detail.
- When tests reveal spec/implementation mismatches, document gaps in `.sisyphus/evidence/` files with source, spec reference, current behavior, and rationale for deferral. Confirm zero canonical spec changes needed.

## Layer checks

- Load `layer-and-segment-rules.md` only when layer choice, segment placement, or dependency direction changed.
- Apply the layer-specific review checklist from `layer-and-segment-rules.md` once one of those conditions is true.
- Load `package-extraction-posture.md` only when the task changes package-facing boundaries or extraction readiness.
- When needed, use search-based proof for known failure modes such as widget-owned `Api/`, reverse imports, or page-specific logic leaking downward.

## FSD checks

- Apply `layer-and-segment-rules.md` and `public-boundary-spec.md` only when layer choice, slice boundary, or segment naming changed.

## Boundary and test checks

- When slice-boundary changes are involved, load and apply `public-boundary-spec.md` checks.
- When reducer or integration tests change, load and apply `testing-playbook.md` checks.
- When coordinator or adapter code changes, verify at least one focused test covers the real callback → reducer → effect chain instead of routing-only interception.
- When semantics depend on branch kind or lifecycle outcome, verify the distinct success, failure, cancel, reload, and teardown paths separately.

## Few-shot examples

- **Bad:** Verification stops after a routing assertion because the callback reached the reducer boundary.
  **Good:** Continue until at least one focused test proves the downstream reducer/effect behavior too.

- **Bad:** Verification treats all lifecycle outcomes as equivalent because the same callback family handled them.
  **Good:** Verify the distinct branch outcomes separately when success, failure, cancel, reload, or teardown are supposed to behave differently.
