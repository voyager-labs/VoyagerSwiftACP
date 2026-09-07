---
description: "Xcode/SPM test-plan visibility safeguard: ensure intended test targets are actually executed."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# Xcode/SPM Test Visibility

## Outcome

- Before relying on test output, identify the intended owner and route: one SwiftPM package suite or one macOS app suite/flow.
- Treat "build succeeded" as distinct from "all intended tests executed and passed".
- When acceptance criteria require SwiftPM package test execution, use the package-local route from `.agents/skills/code-tooling/SKILL.md`.
- Judge package and app coverage independently. A scheme result does not imply package coverage, and a package result does not imply app coverage.

## Default Actions

1. Identify the owner, package or project path, test target, and intended suite or flow.
2. Choose the executor from the capability matrix in `.agents/skills/code-tooling/SKILL.md` before starting a build or test operation.
3. Inspect the selected executor's output or repository task log for suite identity, executed count, and exit code.
4. Compare the intended suite with the executed suite and record an owner-specific receipt.

## Decision Rules

- For a package build, use `xcrun swift build --package-path <path>`.
- For a package-focused outcome, use `xcrun swift test --package-path <path> --filter <suite>`. A project test result does not substitute for this outcome, even when the app scheme consumes the package.
- For a package-wide outcome, use `xcrun swift test --package-path <path>` and inspect the package's own test target output.
- For a simulator project test outcome, stop and record a coverage gap unless the repository defines a canonical simulator test task that exposes executed target names.
- For a mapped macOS flow, use `mise run macos-test-flow -- --flow <flow-id>`.
- For a general macOS app suite, use `mise run macos-test -- -only-testing:VoyagerTests/<suite>`; do not require a full scheme run to prove a named suite.
- For a full macOS scheme outcome, use `mise run macos-test` and inspect its target and suite output.
- An explicit `.xcctestplan` describes app target membership only. Its absence of a package target is not a package-local test failure and does not by itself require a test-plan change.

## Stop Conditions

- Do not assume that a passing run executed the intended suite, or that a build proves test execution.
- Stop and record a selection proof gap when the package path, target, suite, or flow cannot be identified. A broad run cannot replace a missing focused selection.
- Stop and record `test-discovery` when the intended suite is absent or its executed count is zero, even if the process exits zero.
- Classify dependency resolution, compilation, and linking failures before claiming any test execution evidence.
- Do not invent an unavailable platform operation, and do not replace an existing repository task with raw `xcodebuild`.
- Stop and record a coverage gap when the selected executor cannot identify the executed suite or no matrix-supported route exists.

## Verification

- **Package pass**: The selected package path and suite identity match, the executed count is positive, the exit code is zero, and the intended assertions pass.
- **App pass**: The selected app route and suite or flow identity match, the executed count is positive, the exit code is zero, and the intended assertions pass.
- A package pass and an app pass are separate receipts. Neither one is inferred from the other.
- Record `selection`, `dependency-resolution`, `compilation`, `linking`, `test-discovery`, or `test-execution` as the failure phase when applicable. Use `N/A` only for a successful receipt.
- Record the task outcome separately using `pass`, `fail`, `degraded`, `exception`, or `blocked`.
