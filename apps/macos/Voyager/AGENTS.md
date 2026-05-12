# Agent Instructions (Voyager)

Scope: `apps/macos/Voyager/**`

- Follow root gateway: `../../../AGENTS.md`
- Load core contract: `../../../.agents/rules/00-core/00-execution-contract.md`
- Apply macOS domain rules: `../../../.agents/rules/30-macos/00-macos-rules.md`
- For HTTP/bootstrap/env changes: `../../../.agents/rules/30-macos/01-http-and-env.md`

## PR review rules

Voyager-specific PR review policy for `apps/macos/Voyager/**` lives in `../../../.greptile/rules.md`.

- Codex and other agents should read that file when performing PR reviews for this scope.
- Keep this file focused on agent routing and macOS rule entry points; do not duplicate PR review checklists here.
