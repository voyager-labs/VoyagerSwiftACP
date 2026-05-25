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

One spec = one owning test suite named `<SpecID><PascalCaseSpecTitle>Tests.swift`. Interaction ACs = `// MARK:` sections inside that suite. Every interaction test method has a `///` traceability doc comment with scenario, verification content, preconditions, and expected result. Infrastructure = `Support/`. No `FeatureTests` suffix. Focused filters use the suite class name, not the test target name. Hand off to `testing` skill for execution.

## Instructions

1. Load `references/authoring-workflow.md` for the end-to-end spec AC authoring process.
2. Load `references/spec-test-topology.md` before creating or renaming test files, classes, directories, or support files.
3. Load `references/tca-test-authoring.md` before writing `TestStore` assertions, reducer dependency overrides, effect recorders, or async ordering tests.
4. Do not load all three references at once unless both topology creation and TCA authoring happen in the same task. If only naming or renaming files, load only `references/spec-test-topology.md`.
5. Use one spec-owner suite named `<SpecID><PascalCaseSpecTitle>Tests.swift`; do not add `FeatureTests` to new spec AC suites.
6. Put interaction AC scenarios inside the owning suite as `// MARK: - <spec-id>-<interaction_id>` sections.
7. Before every executable interaction test method, write a `///` doc comment using the required traceability shape: first line `<SPEC-ID>-<interaction_id>: <scenario>`, then one intent sentence, then `- 검증 내용`, `- 사전 조건`, and `- 기대 결과` bullets.
8. Put fixtures, recorders, dependency doubles, builders, and helper assertions under `Support/`; support files must not own product behavior.
9. After authoring, hand off to `../testing/SKILL.md` for focused command selection, execution, failure analysis, and reruns; the initial filter should target the suite class such as `--filter ONB004FinishOnboardingTests`, not `--filter VoyagerPagesOnboardingTests`.
