# Voyager Verification Policy

Use this reference after the owning role selects the changed behavior. Repository commands are the verification interface across agents; no particular CodeGraph, OMO, editor or LSP installation is required to execute them. Use semantic tooling when available and disclose narrower syntax/text evidence when it is not.

## Scope

- Run focused package tests first; broaden when shared reducers, package APIs or dependencies change.
- For package graph/product/target/consumer changes, apply `package-integration.md`; package-local results alone do not prove downstream consumers. Run the affected downstream suites once after implementation convergence as required by the repository root instructions.
- For Swift 6 work, load `swift6-package-rules.md` and build the package directly.
- For callbacks/multi-step async work, test boundary behavior plus downstream effects: cancellation, supersession, stale completion, persistence, partial application and teardown.
- Verification should match the changed concern. Do not repeat full suites after each intermediate edit or invent a broad UI automation matrix for a presentation-only change.

## Style and deterministic check entrypoints

```bash
python3 -m scripts.run_swift_checks --staged
python3 -m scripts.run_swift_checks --working-tree
python3 -m scripts.run_swift_checks --base-ref <base-sha>
python3 -m scripts.run_swift_checks --all --checks ast
python3 -m scripts.validate_harness --staged --with-build-matrix
python3 -m scripts.verify_plan --staged
python3 -m unittest discover -s scripts/tests
mise exec -- ast-grep test --skip-snapshot-tests
```

- `run_swift_checks` is read-only. Staged sources and rule/config files are inspected from an exported Git index; base-ref source checks use committed HEAD. Working-tree evidence is explicitly mutable. Do not substitute one scope for another.
- Policy/config-only changes expand the relevant engine to the tracked source scope; a source-only glob must not skip them.
- Explicit `--checks` selects partial stages. It does not prove omitted stages. The runner is not an app compiler or a complete ownership checker.
- `validate_harness` alone checks harness structure; its receipt says buildMatrix notRun. Hooks and PR CI add `--with-build-matrix` and require the matrix in the same content root. A missing project or script fails a requested composite gate rather than silently making it optional.
- Use the versions pinned in `mise.toml`. Required tool absence, invalid input and timeouts are blocked, not success. Do not silently install substitutes or weaken rules.
- The PR workflow runs Python regressions and the pinned ast-grep match/no-match fixture corpus. This does not imply macOS SwiftLint/SwiftFormat or Xcode ran on Linux.
- The explicit `scripts/lint-and-format-macos.sh <root>` command mutates formatting; it is not the read-only hook path. It probes required tools before formatting and preserves failures.

## Tool responsibility and evidence limits

SwiftFormat owns agreed layout/style transformations. SwiftLint owns configured code-quality diagnostics; `analyzer_rules` require a separately executed analyzer path with suitable compile evidence and are not covered by normal lint. Do not claim those checks ran from configuration alone.

AST rules own narrow syntax and declared applicability. Valid/invalid/descendant-bypass fixtures are required for changed rules. A `--skip-snapshot-tests` pass checks matches, not golden diagnostic output. Warnings are review signals; errors block. A Coordinator allowance does not prove geometry-only behavior, teardown or single-writer correctness.

Use searches to find candidate stale routes and duplicate writers, not to prove global semantic properties. Compiler/access control, TestStore state transitions and native lifecycle tests cover different claims. Performance claims require actual Release measurements or specific work-count tests; do not invent speedup ratios.

Report commands, input ref/tree, selected stages, exit codes, first failure and corrected rerun. Distinguish passed, failed, blocked, notApplicable and notRun. Any required stage that is blocked/notRun prevents a complete-verification claim. Source-contract shadow corpus checks policy text; it does not execute or score an agent's behavior.

## Runtime Unified Logging

Derive subsystem values from the exact built `.app` that will be launched. Resolve the app first, then read its `Contents/Info.plist`:

```bash
app_path="/path/to/the/resolved/Voyager.app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
```

Use that `CFBundleIdentifier` for `log show`/`log stream` predicates, not hard-coded `com.voyager.app` or `com.voyager.helper`. The canonical namespace is `fm.voyager.*`, but actual suffixes come from the resolved build. An observed marker's subsystem can be checked against that bundle.

For cross-process delivery, observe app and Helper sides; different identifiers such as `fm.voyager.Voyager.dev` and `fm.voyager.VoyagerHelper.dev` are legitimate. Prefer bounded marker filtering, for example `eventMessage CONTAINS[c] "voyager.fs.delivery" OR eventMessage CONTAINS[c] "app_activation"`, then correlate ordering inside a bounded t0 window.

Keep evidence privacy-safe: never print raw filesystem/watch paths, payloads, userInfo or object data. Record marker names, emitting bundle/subsystem, timestamps, ordering and exit/classification results only.
