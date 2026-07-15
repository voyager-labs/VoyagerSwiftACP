---
description: "Fixture source rules for Voyager macOS entry manipulation tests."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# Entry Fixture Source Rules

## Outcome

- This is the canonical owner for entry fixtures: real entry scenarios use the root `fixtures/` submodule payload at `fixtures/fixtures/**`, helpers live in the consuming target's `Support/`, mutations use isolated sandbox copies, and OS side effects stay mocked.

## Default Actions

1. For entry, collection, `.voycoll`, ingestion, metadata, path-display, or File Manager tests, load `.agents/skills/voyager-dev/implementer/spec-test-authoring/SKILL.md` and select the smallest representative `fixtures/fixtures/**` category.
2. Initialize the submodule, use repo-relative fixture paths in helpers/comments/evidence, and keep a target-local flat `Support/` path helper.
3. Use `FixtureSandbox.copyingFile(from:)` or `copyingDirectory(from:)` with deferred cleanup for reducer action inputs that mutate, rename, delete, write metadata, change permissions, or create path variants.
4. Use direct read-only fixture paths only for non-mutating inspection; mock `NSWorkspace`, QuickLook, sharing, pasteboard, Trash, and other OS-boundary clients.

## Decision Rules

- Real fixture paths go in and mocked OS clients come out. Empty-path no-op tests are exempt because they do not touch the file system.
- Build path-normalization, symlink, standardized-path, and `/tmp` ↔ `/private/tmp` comparisons from the same sandboxed real fixture and actual filesystem links; verify both paths exist and canonicalize equally.
- Add reusable binary, provenance-sensitive, or Voyager-owned samples through `voyager-test-files`, not this repository.

## Stop Conditions

- Do not use machine-local/ad-hoc paths, duplicate reusable binary fixtures under tests, mutate `fixtures/fixtures/**`, or replace real entry coverage with trivial temporary text files.
- Do not use hard-coded fake non-empty reducer input paths; use a target-local sandbox helper backed by the canonical fixture source.
- Do not import another target's fixture helper unless it is intentionally exposed through shared test support.

## Verification

- Confirm `git submodule status fixtures` and `test -d fixtures/fixtures` prove the fixture source is available.
- Confirm mutation tests use temporary copies and originals remain intact; confirm no reusable binary fixture was added under macOS tests.
- Record the focused command and fixture path/category in verification evidence.
