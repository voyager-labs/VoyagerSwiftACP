# Voyager Dev Development Rules

Use this file to accumulate Voyager-local development heuristics that are reusable across many tasks but are not yet broad enough for `.agents/rules/**`.

## Current rules

- Let `voyager-dev` classify task shape internally; do not push explicit mode selection onto the user.
- Load multiple playbooks together when a change spans scaffolding, decomposition, observation ownership, and reuse discovery.
- Prefer reducer-owned external/system observation and keep views as lifecycle/action senders only.
- Prefer explicit composition through dedicated model types, helper/coordinator types, and child reducers/features over letting `State+*`, `Action+*`, `Feature+*`, or `Reducer+*` files carry hidden ownership and state-flow splits.
- Default to reusing existing models, reducers, and helper objects before inventing new ones.
- If an existing type can absorb the change by adding properties or well-scoped behavior without breaking ownership, prefer extending that type over creating a sibling wrapper or near-duplicate model.
- Create a new model/object/reducer only when the responsibility is large enough to deserve its own clearly named scope, not just to make one call site look cleaner.
- Avoid compatibility-only shells that merely wrap an existing type or flow without owning new behavior, new boundaries, or meaningful complexity reduction.
- Do not force a single Action taxonomy on every Voyager feature.
- Do not leave reducer composition style entirely to local preference when it changes ownership shape or feature boundaries.
- Prefer `Scope` when a child owns dedicated substate/action and forms a real feature boundary with reuse, lifecycle, or independent test value.
- Prefer reducer-module composition (for example `CombineReducers` or explicit parent-owned reducer assembly) when multiple concerns still share the same parent state/action and do not deserve separate child feature boundaries.
- Avoid large non-trivial same-file private helper reducer `.merge` structures when dedicated reducer modules would make ownership clearer.
- For UI-facing features, prefer `view` / `internal` / `delegate` (+ child action) families.
- For operation/orchestration hubs whose reducers are already split by domain, domain-family nested actions are allowed and often preferred.
- Do not mirror reducer filenames 1:1 into action namespaces; choose stable domain families instead.
- Keep cross-cutting status, metrics, and lifecycle actions flat or narrowly grouped when domain nesting would reduce clarity.
- Optimize for readability and ownership clarity, not taxonomy purity.
- Keep Voyager-specific heuristics here until they become stable enough to enforce repo-wide, then promote them into `.agents/rules/**`.

## Promotion test

- Keep a heuristic here while it is Voyager-specific, evolving, or mostly procedural.
- Move a heuristic into `.agents/rules/**` when it becomes a stable invariant that should apply automatically by path.
