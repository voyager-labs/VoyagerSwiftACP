---
description: "Fixture source rules for Voyager macOS entry manipulation tests."
globs: "apps/macos/**/*.swift"
---

# Entry Fixture Source Rules

## Applies when

- Authoring tests that create, import, copy, move, rename, delete, index, preview, or otherwise manipulate entries.
- Authoring tests that inspect entry metadata, file type handling, document ingestion, thumbnails, search/index inputs, or file-backed entry state.
- Authoring tests for entry collections: listing, sorting, grouping, filtering, selection, multi-selection, pagination, search result sets, navigation, batch operations, collection file open/save, or Voyager collection formats such as `.voycoll`.
- Authoring File Manager tests that display, normalize, sort, group, navigate, or render entry paths.
- Creating test support helpers that need representative files, directories, file names, extensions, sizes, or metadata.

## Must

- Use the repository root `fixtures/` submodule as the default source for entry test files, entry collections, and Voyager-owned fixture formats such as `.voycoll`. The imported payload lives under `fixtures/fixtures/`.
- Refer to fixture files by repo-relative paths such as `fixtures/fixtures/images/jpeg/hopper.jpg` in test comments, helper names, and evidence.
- Initialize the submodule before fixture-backed verification: `git submodule update --init --recursive` or `mise run submodules`.
- Keep reusable fixture path helpers in the relevant test target's `Support/` directory; helpers may resolve the repo root with `git rev-parse --show-toplevel` or test-process environment, but tests should consume stable repo-relative fixture paths.
- Copy fixture files into a temporary test directory before any test mutates, renames, deletes, writes metadata, changes permissions, or asserts destructive entry operations.
- Use read-only fixture paths directly only for tests that inspect path display, metadata, detection, indexing input, collection state, or import source identity without mutating the source.
- In interaction/spec tests, mention the fixture path or fixture category in the `- 사전 조건` traceability bullet when the scenario depends on real files.
- Use `FixtureSandbox.copyingFile(from:)` or `FixtureSandbox.copyingDirectory(from:)` to create isolated temp copies of real fixture files for reducer action inputs. Pair with `defer { sandbox.cleanup() }` to guarantee sandbox teardown. Use `sandbox.fileURL.path` as the action input path so the reducer receives a real, existing file path.
- Mock OS-boundary clients (NSWorkspace, QLPreviewPanel, share services, pasteboard, Trash) even when using real fixture paths. Test the reducer's file-operation logic, not real OS side effects. The pattern is: **real paths in, mocked clients out**.
- Empty-path no-op tests (where the action path is empty and no file operation occurs) are exempt from `FixtureSandbox` usage — they do not interact with the file system.

## Must not

- Do not depend on machine-local paths such as `~/Desktop`, `~/Downloads`, user home directories, or ad-hoc files outside the repo.
- Do not duplicate binary fixture files under `apps/macos/**/Tests/**`; add reusable samples to the `fixtures/` submodule instead.
- Do not mutate files in `fixtures/fixtures/**` in-place during tests.
- Do not create new large, provenance-sensitive, or reusable Voyager-owned fixture files (including `.voycoll`) directly in `voyager-app`; import them through `voyager-test-files` with source/license notes.
- Do not skip fixture-backed coverage by generating trivial temporary text files when the behavior under test manipulates real entries, entry collections, `.voycoll` files, file types, paths, metadata, thumbnails, indexing, ingestion, or File Manager presentation.
- Do not use hardcoded fake paths (e.g., `/Users/test/document.txt`, `/tmp/fake*`) as reducer action inputs in non-empty-path test scenarios. Use `FixtureSandbox` to provide real file paths instead. Fake paths are acceptable only in mock return values (e.g., a mocked app URL) or empty-path no-op tests.

## Execution steps

1. Pick the smallest representative fixture category that exercises the entry or collection behavior (`documents`, `images`, `media`, `archives`, `data`, `models`, `spreadsheets`, `texts`, `presentations`, or a Voyager-specific collection fixture category for `.voycoll`).
2. Resolve fixture paths through a test support helper instead of scattering path construction across test methods.
3. For mutation/destructive entry tests, copy fixtures into an isolated temporary directory and assert the original fixture still exists afterward.
4. For entry collection, `.voycoll`, path-display, and File Manager presentation tests, prefer directory trees rooted under `fixtures/fixtures/**` or a temporary copy of fixture subsets so rendered paths match realistic names, extensions, folder nesting, and mixed file types.
5. Record the focused test command and fixture paths used in verification evidence.

## Verification

- `git submodule status fixtures` shows the fixture source is initialized.
- `test -d fixtures/fixtures` confirms the imported payload is present.
- No new binary or reusable Voyager-owned test fixture files appear under `apps/macos/**/Tests/**` when an equivalent `fixtures/fixtures/**` sample exists or should be added there.
- Fixture-mutating tests operate on temporary copies, not `fixtures/fixtures/**` directly.
