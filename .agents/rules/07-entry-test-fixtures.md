---
description: "Require the shared fixture corpus for Entry-related Swift and Go tests."
globs: "{apps/macos/**/*.swift,apps/entry-core/**/*_test.go}"
schemaVersion: 2
---

# Entry Test Fixtures

## Outcome

- Entry-related Swift and Go tests use representative files from the root `fixtures/` submodule payload at `fixtures/fixtures/**`.
- The shared corpus remains read-only; tests perform mutations on isolated temporary copies.
- macOS-specific helper mechanics remain owned by [Entry Fixture Source Rules](.agents/skills/voyager-dev/implementer/spec-test-authoring/references/entry-fixture-source.md).

## Default Actions

1. Select the smallest existing fixture category that represents the behavior under test.
2. Verify the submodule payload is available before running fixture-dependent tests.
3. Copy files or directories into a target-local temporary sandbox before rename, delete, write, permission, metadata, or path-variant operations.
4. Record the repository-relative fixture path and focused verification command in task evidence.

## Decision Rules

- Read fixtures directly only for non-mutating inspection.
- Use generated or in-memory data only when behavior does not depend on a real file format, metadata shape, ingestion path, or filesystem entry.
- Add reusable, binary, provenance-sensitive, or Voyager-owned samples to `voyager-test-files`; do not duplicate them in application test targets.
- Keep platform-specific path helpers local to their test target unless shared test support intentionally exposes one.

## Stop Conditions

- Do not mutate `fixtures/fixtures/**`, use machine-local paths, duplicate reusable fixtures, or replace representative Entry coverage with trivial temporary files.
- Do not skip fixture-dependent tests when the submodule is absent; fail with setup guidance.
- Do not introduce a new fixture-root environment variable or command wrapper when repository-relative resolution already works through the owning test entrypoint.

## Verification

- Run `git submodule status fixtures` and `test -d fixtures/fixtures`.
- Run the focused fixture-dependent test and confirm it reads the shared source while mutations remain confined to temporary storage.
- Confirm the fixture submodule has no working-tree changes after the test.
