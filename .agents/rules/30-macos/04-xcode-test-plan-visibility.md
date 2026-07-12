---
description: "Xcode/SPM test-plan visibility safeguard: ensure intended test targets are actually executed."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# Xcode/SPM Test-Plan Visibility

## Outcome

- Before relying on test output, verify that the active test plan includes all intended test targets — not just project-level targets.
- Treat "build succeeded" as distinct from "all intended tests executed and passed".
- When acceptance criteria require SPM package test execution, use the package-local SwiftPM route unless an explicit Xcode test plan proves the package target runs.

## Default Actions

1. Identify the project and package test targets required by the acceptance criteria.
2. Choose the executor from the capability matrix in `.agents/skills/code-tooling/SKILL.md` before starting a build or test operation.
3. Inspect executed target names from the selected executor's structured result or repository task log.
4. Compare intended targets with executed targets and record the result in verification evidence.

## Decision Rules

- For a package-local test outcome, run the focused `xcrun swift test --package-path <path>` route. A project test result does not substitute for this outcome unless its executed targets explicitly include the package suite.
- For a simulator project test outcome, use XcodeBuildMCP only after `session_show_defaults` confirms a project, scheme, and simulator; use its test result to establish executed target parity.
- For a macOS scheme test outcome, use the existing `mise run macos-test` repository task because the currently exposed MCP surface has simulator-only build/test operations. If the task needs a focused result, record that the repository task is a broader fallback before inspecting its recorded result/log for target parity.
- When an explicit `.xcctestplan` exists, use it as the source for intended target membership. An auto-created plan is not proof that all package targets executed.

## Stop Conditions

- Do not assume that a passing test run executed every intended target, or that a build proves test execution.
- Do not invent an unavailable XcodeBuildMCP macOS or device operation, and do not replace an existing repository task with raw `xcodebuild`.
- Stop and record a coverage gap when the selected executor cannot identify executed targets, an intended package suite is absent, or no matrix-supported route exists.

## Verification

- **PASS**: Every intended test target (project + SPM package) appears in the test output.
- **FAIL**: Any intended test target is absent from the output.
- On FAIL, create or fix the `.xcctestplan` when that is in scope; otherwise record the limitation and stop before claiming coverage.

**Illustrative example:**

A scheme referencing SPM packages under `apps/macos/Packages/**` may have an auto-created test plan that only includes `VoyagerTests` but skips package targets such as `VoyagerPagesSettingsTests` or `VoyagerEntitiesAiTests`. The verification command above would surface this gap as a FAIL.
