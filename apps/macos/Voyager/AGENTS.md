# Agent Instructions (Voyager)

Scope: `apps/macos/Voyager/**`

- Follow root gateway: `../../../AGENTS.md`
- Load core contract: `../../../.agents/rules/00-core/00-execution-contract.md`
- Apply macOS domain rules: `../../../.agents/rules/30-macos/00-macos-rules.md`
- For HTTP/bootstrap/env changes: `../../../.agents/rules/30-macos/01-http-and-env.md`

## Review guidelines (Voyager)

In addition to the root review guidelines, the reviewer should apply these Voyager-specific checks when reviewing changes under `apps/macos/Voyager/**`.

### Always check

- Whether side effects (network, filesystem, system SDK calls) are kept out of SwiftUI views and routed through reducers or dependency clients.
- Whether reducer and service ownership is unambiguous — each cross-layer concern should have exactly one canonical owner.
- Whether cleanup, reset, or teardown responsibility is owned by a single location, not duplicated across success handlers, session-end hooks, and reload paths.
- Whether the change follows FSD dependency direction and does not introduce reverse imports (e.g., Entities importing Features/Pages).
- Whether context (resolved state, user intent, session data) is preserved across async/callback chains instead of being re-derived from weaker transient inputs.
- Whether the change adds a compatibility-only wrapper or near-duplicate type when extending or reusing an existing abstraction would suffice.
- Whether cross-feature mutations go through actions or delegate events rather than direct state access.

### Skip

- Anything already covered by the root Skip policy.
- SwiftUI view body structure suggestions that do not relate to side-effect leakage or ownership.
- Minor TCA boilerplate style preferences without structural implications.
