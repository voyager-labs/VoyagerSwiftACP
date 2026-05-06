# Voyager Dev XcodeBuildMCP Workflow

Use this reference when the task needs Xcode project listing, build, or test execution for Voyager.

## Preferred path

- Prefer XcodeBuildMCP tools over raw `xcodebuild` CLI when the MCP server is already available in the client.
- Use XcodeBuildMCP first for:
    - project or scheme listing
    - build execution
    - focused or full test execution
- Do not default to raw `xcodebuild` if XcodeBuildMCP is already installed and reachable.

## Harness setup expectation

- XcodeBuildMCP must already be wired into the current harness before the agent can use it.
- In this repository, `opencode.json` already declares XcodeBuildMCP for `opencode` sessions.
- For any other CLI or harness, ask the user to add the equivalent XcodeBuildMCP configuration to that harness themselves.
- Do not assume one client command works everywhere; the exact config shape depends on the harness.

## If XcodeBuildMCP is missing

- If the client does not expose XcodeBuildMCP tools yet, guide the user to install or configure it before continuing with build/test-heavy work.
- Do not assume the agent should run `codex mcp add` itself.
- Instead, ask the user to add XcodeBuildMCP in the harness they are actually using.
- For Codex CLI, one concrete command the user can run is:

```bash
codex mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp
```

- The equivalent `~/.codex/config.toml` entry is:

```toml
[mcp_servers.XcodeBuildMCP]
command = "npx"
args = ["-y", "xcodebuildmcp@latest", "mcp"]
```

## If `npx` is missing

- Do not silently fall back to raw `xcodebuild` for the main recommended workflow.
- Tell the user that the recommended `npx`-based XcodeBuildMCP setup requires `npx`, which usually means installing Node.js 18+ so `npx` is available.
- After `npx` is available, ask the user to add XcodeBuildMCP to the harness they are using, or use the Codex example above when the harness is Codex CLI.
- If the user does not want a Node-based install, mention the Homebrew alternative:

```bash
brew tap getsentry/xcodebuildmcp
brew install xcodebuildmcp
```

## Requirements

- macOS 14.5 or later
- Xcode 16.x or later
- Node.js 18.x or later for the `npx` flow

## Verification posture

- Once XcodeBuildMCP is available, use its project-listing, build, and test tools for verification.
- Until then, treat the missing MCP as an environment/setup blocker and surface the exact harness-specific install step to the user.
- Keep the repository-specific verification expectations from `verification.md`:
    - focused tests first when possible
    - expand to the full suite when shared reducers or cross-feature boundaries changed
    - run SwiftLint and SwiftFormat for touched Swift files
