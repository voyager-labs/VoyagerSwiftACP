---
name: spec-test-authoring
description: Guides Voyager macOS Swift/TCA spec AC test authoring and topology. Use when creating, restructuring, or maintaining tests from feature specs, acceptance criteria, interaction IDs, TestStore flows, or test support files before running verification. Triggers on: spec tests, AC tests, interaction tests, TestStore authoring, test topology, test support.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: verifier
    shape: spec-test-authoring
---

# Voyager Dev Spec Test Authoring

## Core rule

One spec = one owning test suite named `<SpecID><PascalCaseSpecTitle>Tests.swift`. Interaction ACs = `// MARK:` sections inside that suite. Every interaction test method has a `///` traceability doc comment with scenario, verification content, preconditions, and expected result. Infrastructure = `Support/`. No `FeatureTests` suffix. Focused filters use the suite class name, not the test target name. Canonical flow documents own production-composition suites under `VoyagerTests/Flows/`; spec-owner suites own interaction-level AC detail. Hand off to `testing` skill for execution.

## Instructions

1. Load `references/authoring-workflow.md` for the end-to-end spec AC authoring process.
2. Load `references/spec-test-topology.md` before creating or renaming test files, classes, directories, or support files.
3. Load `references/tca-test-authoring.md` before writing `TestStore` assertions, reducer dependency overrides, effect recorders, or async ordering tests.
4. Do not load all three references at once unless both topology creation and TCA authoring happen in the same task. If only naming or renaming files, load only `references/spec-test-topology.md`.
5. Use one spec-owner suite named `<SpecID><PascalCaseSpecTitle>Tests.swift`; do not add `FeatureTests` to new spec AC suites.
6. Put interaction AC scenarios inside the owning suite as `// MARK: - <spec-id>-<interaction_id>` sections.
7. Before every executable interaction test method, write a `///` doc comment using the required traceability shape: first line `<SPEC-ID>-<interaction_id>: <scenario>`, then one intent sentence, then `- 검증 내용`, `- 사전 조건`, and `- 기대 결과` bullets.
8. Put fixtures, recorders, dependency doubles, builders, and helper assertions under `Support/`; support files must not own product behavior.
9. For entry-manipulation, entry collection, `.voycoll`, or entry path-display specs, apply `.agents/rules/30-macos/09-entry-fixture-source.md`: default real-file scenarios to the root `fixtures/` submodule fixture source (`fixtures/fixtures/**`), keep fixture helpers in the current test target's flat `Support/` directory, and document the fixture path/category in the traceability precondition.
10. After authoring, hand off to `../testing/SKILL.md` for focused command selection, execution, failure analysis, and reruns; the initial filter should target the suite class such as `--filter <SpecID><PascalCaseSpecTitle>Tests`, not the test target name.
11. When an interaction doc has `status: "planned"` but the AC is not yet implemented, load `references/incomplete-interaction-protocol.md` for the XCTSkip placeholder pattern, doc status → test action mapping, and lifecycle rules. Do not write XCTSkip for `"drafted"`, `"deprecated"`, or `[DECISION NEEDED]` interactions.
12. Never create standalone component or infrastructure test files (e.g. `AccountTokenFileStoreTests.swift`, `EnvironmentLoaderTests.swift`) as ad-hoc proof for an implementation change. `Specs/` contains ONLY spec-owner suites. If implementation behavior needs coverage but no spec AC exists, update the spec document to add the AC first, then add test methods to the owning spec-owner suite under the appropriate `// MARK:` section. If the user did not ask for test authoring, stop at existing-test/build evidence and report the proof gap. See `references/spec-test-topology.md` section "Specs/ directory contents" and "Component behavior coverage workflow".
13. If the test request originates from a canonical flow document (e.g. `access_unlock_flow.md`), load `references/flow-test-topology.md` and create the suite under `VoyagerTests/Flows/<CATEGORY>/`, not under `Specs/`.

## Second-pass rules

These rules codify patterns discovered during spec-test hardening (VOY-356). Load the referenced files for full detail.

1. **Canonical `// MARK` format**: Headings must match `// MARK: - [A-Z]{2,4}-\d{3}-[a-z0-9_]+`. No Korean text, descriptions, or parenthetical notes. See `references/spec-test-topology.md` section "Section rules".
2. **`store.exhaustivity = .off` rationale**: Every override needs an adjacent Korean rationale comment. See `references/tca-test-authoring.md` section "Exhaustivity".
3. **`store.finish()` selective criteria**: Apply only for fire-and-forget effects and unconsumed async lifecycles. See `references/tca-test-authoring.md` section "`store.finish()` application criteria".
4. **Flat Support naming**: Keep support files directly under `Support/` and name them by role/type, not by spec ID or subdirectory. See `references/spec-test-topology.md` section "Support rules".
5. **Scenario-specific dependency injection first**: Before creating a new shared `*Double` or `*Mock` file, check whether `withDependencies { $0.xxx = ... }` inline overrides per-test suffice. Promote to a shared double only when 3+ tests reuse the same override pattern. This avoids premature abstraction in test support code.
6. **OS boundary mock/manual split**: For specs involving OS integration (Open, QuickLook, Share, Services, Finder reveal, Pasteboard, Trash, Tags), keep test input data real (actual fixture paths, real file extensions) but mock the boundary client (e.g. `NSWorkspace`, `QLThumbnailGenerator`). Actual UI side effects are manual-only test surface; never assert OS UI state in automated tests.
7. **Path-equivalence fixtures must be real**: For symlink, standardized-path, `/tmp` ↔ `/private/tmp`, or canonicalization tests, derive both path strings from the same sandboxed `fixtures/fixtures/**` file and real filesystem links. Do not hardcode paired fake paths just to exercise string normalization.
