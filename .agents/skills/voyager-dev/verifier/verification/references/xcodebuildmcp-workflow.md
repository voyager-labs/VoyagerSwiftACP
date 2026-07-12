# Voyager Dev XcodeBuildMCP Workflow

Use this reference when the task needs a simulator XcodeBuildMCP operation for Voyager. The capability matrix in `.agents/skills/code-tooling/SKILL.md` selects the executor for every verification scope.

## Preferred path

- Prefer XcodeBuildMCP tools when the MCP server exposes an operation that supports the required simulator scope.
- Use XcodeBuildMCP first for:
    - project or scheme listing
    - build execution
    - focused or full test execution
- Inspect `session_show_defaults` before the first available MCP build, run, or test operation in a session.

## Harness setup expectation

- XcodeBuildMCP must already be wired into the current harness before the agent can use it.
- In this repository, `opencode.json` already declares XcodeBuildMCP for `opencode` sessions.
- For any other CLI or harness, ask the user to add the equivalent XcodeBuildMCP configuration to that harness themselves.
- Do not assume one client command works everywhere; the exact config shape depends on the harness.

## Unsupported capability

- For macOS scheme verification, use the existing `mise run macos-build` or `mise run macos-test` route selected by the matrix.
- For package-local verification, use the matrix-selected `xcrun swift build` or `xcrun swift test --package-path` route.
- For physical-device work or a simulator request not supported by an exposed MCP operation, stop and report the missing capability. Do not install/configure MCP tools or call raw `xcodebuild` as an ad-hoc substitute.

## Verification posture

- Once an operation is both available and scope-compatible, use its project-listing, build, and test tools for simulator verification.
- Otherwise, follow the matrix fallback or stop condition rather than treating missing MCP as a universal blocker.
- Keep the repository-specific verification expectations from `verification.md`:
    - focused tests first when possible
    - expand to the full suite when shared reducers or cross-feature boundaries changed
    - run SwiftLint and SwiftFormat for touched Swift files
