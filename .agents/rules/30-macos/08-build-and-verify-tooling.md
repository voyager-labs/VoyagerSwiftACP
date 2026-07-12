---
description: "macOS verification executor routing."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# Build and Verify Tooling

## Outcome

- Preserve the verification outcomes and tiers owned by `.agents/rules/00-core/02-verification.md`.
- Select an executor by actual supported capability rather than treating any one tool as universal.
- Keep repository `mise` tasks usable for human, CI, and agent fallback paths when they match the required outcome.

## Default Actions

1. Determine the required Tier 1, Tier 2, or Tier 3 outcome before choosing a tool.
2. Load `.agents/skills/code-tooling/SKILL.md` and use its capability matrix.
3. For the first available XcodeBuildMCP build, run, or test operation in a session, inspect defaults with `session_show_defaults`.
4. Record the selected executor, command or MCP operation, scope, tier, result, and any coverage or capability gap.

## Decision Rules

- Prefer XcodeBuildMCP when its exposed operation supports the required simulator scope and defaults are configured.
- Use `xcrun swift build` or `xcrun swift test` for package-local SwiftPM outcomes; simulator MCP operations do not replace package-local proof.
- Use `mise run macos-build` or `mise run macos-test` for macOS scheme outcomes when the current MCP surface does not expose macOS build/test capability.
- Use the repository `mise exec` SwiftLint and SwiftFormat commands for style outcomes.
- Focused tests precede broader tests. When the current tool surface lacks focused macOS test support, record that capability gap before selecting the matrix's broader `mise run macos-test` fallback.

## Stop Conditions

- Do not use an unexposed XcodeBuildMCP device or macOS operation, create an ad-hoc build script, or call raw `xcodebuild` as an agent fallback.
- Stop with a capability blocker when the matrix has no existing verified fallback for the requested platform or operation.
- Stop before reporting success when the chosen executor cannot prove the required outcome or target coverage.

## Verification

- Confirm executor selection matches the capability matrix and core tier.
- Confirm any unsupported capability records either an existing fallback result or an explicit stop with the missing operation.
