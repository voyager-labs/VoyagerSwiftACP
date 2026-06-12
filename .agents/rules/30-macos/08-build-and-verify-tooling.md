---
description: "Build/test tooling: XcodeBuildMCP mandatory, no fallback."
globs: "apps/macos/**/*.swift"
---

# Build and Verify Tooling

## Must

- Always use **XcodeBuildMCP MCP tools** (`build_sim`, `test_sim`) for building and testing macOS targets.
- Treat XcodeBuildMCP as the **only** build/test path for agent workflows.
- If XcodeBuildMCP fails, investigate and fix the issue — do not fall back to CLI `xcodebuild`.
- The `mise run macos-build` / `mise run macos-test` tasks exist solely for human/CI use.

## Must not

- Run `xcodebuild` directly from bash/terminal as an agent.
- Create ad-hoc build scripts that bypass XcodeBuildMCP.
- Consider CLI `xcodebuild` as a fallback when XcodeBuildMCP has issues.
- Add or reference any agent workflow step that invokes `xcodebuild` directly.

## Rationale

XcodeBuildMCP returns structured results (`warnings[]`, `errors[]`, `buildLogPath`) instead of raw build stdout. This reduces token consumption by orders of magnitude — CLI xcodebuild dumps all compilation noise (CompileC, Ld, CpHeader, etc.) into agent context with no filtering.

## Verification

- Confirm all build/test calls in agent workflows use XcodeBuildMCP tools.
- Confirm no agent rules or agent-facing documentation reference direct `xcodebuild` CLI invocation as an alternative for agent workflows.
