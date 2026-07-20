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
