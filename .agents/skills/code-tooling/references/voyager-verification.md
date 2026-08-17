# Voyager Verification Policy

Use this reference for Voyager task verification after the owning role has selected the changed behavior.

## Scope

- Run focused package tests first; broaden only when shared reducers, package APIs, or dependencies change.
- For package graph, product, target, dependency, or consumer changes, apply `package-integration.md`; package-local evidence alone does not prove downstream consumers.
- For Swift 6 package work, load `swift6-package-rules.md` and build the package directly.
- For callback-heavy or multi-step async work, prove boundary behavior plus the downstream reducer/effect chain, including cancellation, supersession, stale completion, persistence, and teardown paths.

## Style and mechanical checks

- Run SwiftLint and SwiftFormat for touched Swift sources before the final test pass.
- If SwiftFormat scans build output or vendored checkouts, check path resolution before changing formatter config: `.swiftformat` excludes are relative to its file; for an absolute invocation root, use an explicit CLI exclusion for the concrete build directory.
- Use `ast-grep` or targeted text search to prove removal of stale routes, view-owned observation, duplicate cleanup ownership, and invalid persistence after cancellation.
- Report commands, exit codes, first failure, rerun result, and reduced confidence explicitly.

## Runtime Unified Logging

Derive Unified Logging subsystem values from the exact built `.app` that will be launched. Resolve that app first, then read `Contents/Info.plist` and use its `CFBundleIdentifier` as the subsystem value, for example:

```bash
app_path="/path/to/the/resolved/Voyager.app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
```

Construct and validate the `log show` or `log stream` predicate from that value. Do not hard-code `com.voyager.app` or `com.voyager.helper` as Voyager logging namespaces. Voyager's canonical namespace is `fm.voyager.*`, but current suffixes are evidence to derive from the built app, not a substitute for derivation. If a marker is already observed, its subsystem is valid evidence for that emitting process and can be used to check the resolved bundle identity.

For a cross-process delivery chain, observe both the app and Helper sides. They can legitimately use different bundle identifiers, such as `fm.voyager.Voyager.dev` and `fm.voyager.VoyagerHelper.dev`. Prefer marker-text filtering over a guessed subsystem-only predicate, for example `eventMessage CONTAINS[c] "voyager.fs.delivery" OR eventMessage CONTAINS[c] "app_activation"`, then correlate the ordered markers inside a bounded `t0` window. This captures app markers and Helper markers when they are emitted under different subsystems.

Keep predicates and evidence privacy-safe. Never print raw filesystem paths, watch roots, payloads, `userInfo`, or object data. Record only marker names, emitting subsystem or bundle identity, timestamps or bounded windows, ordering, and exit or classification results.
