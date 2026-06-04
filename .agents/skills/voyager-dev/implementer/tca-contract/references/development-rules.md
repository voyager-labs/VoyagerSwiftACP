# Voyager Dev Development Rules

Use this file to accumulate Voyager-local development heuristics that are reusable across many tasks but are not yet broad enough for `.agents/rules/**`.

## Current rules

- Let `voyager-dev` classify task shape internally; do not push explicit mode selection onto the user.
- Load multiple playbooks together when a change spans scaffolding, decomposition, observation ownership, and reuse discovery.
- Prefer reducer-owned external/system observation and keep views as lifecycle/action senders only.
- Prefer explicit composition through dedicated model types, helper/coordinator types, and child reducers/features over letting `State+*`, `Action+*`, `Feature+*`, or `Reducer+*` files carry hidden ownership and state-flow splits.
- When a parent `State` stores another feature's `State` as a child boundary, prefer an explicit property type with `.init()` (for example `var child: ChildFeature.State = .init()`) over relying on initializer-only type inference (`var child = ChildFeature.State()`).
- For `@Dependency` declarations, prefer inferred property types (for example `@Dependency(\.searchClient) var searchClient`) over repeating the client type explicitly; keep the explicit type on the `DependencyValues` accessor and only annotate the use-site declaration when inference fails or real disambiguation is needed.
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
- When a feature owns child reducers through TCA composition, keep the parent-facing action route aligned with the composition case path instead of burying owned child traffic under the parent's `delegate`.
- For ordinary `Scope(state:action:)` children, that usually means a direct top-level child action case on the parent.
- Reserve a parent feature's `delegate` family for outward/upward events it emits to its parent or ancestor, not as a namespace for owned scoped child reducers.
- If a scoped child needs to notify its parent semantically, prefer `child(.delegate(...))` over moving the child's scoped routing under the parent's `delegate`.
- For parent window/page reducers that coordinate several child features plus cross-cutting commands, a flat parent action enum with child feature cases is acceptable when extra family nesting adds ceremony without clarifying ownership.
- For operation/orchestration hubs whose reducers are already split by domain, domain-family nested actions are allowed and often preferred.
- Do not mirror reducer filenames 1:1 into action namespaces; choose stable domain families instead.
- Keep cross-cutting status, metrics, and lifecycle actions flat or narrowly grouped when domain nesting would reduce clarity.
- Optimize for readability and ownership clarity, not taxonomy purity.
- Treat compatibility-only action shells and legacy facades as temporary migration aids. Route new work directly to the canonical owner and remove the facade once call sites converge.
- Prefer parent-owned bridge reducers or translator reducers for child-to-child, child-to-window, and child-to-navigation routing instead of scattering peer mutations across sibling features.
- Keep one canonical owner per concern. When behavior such as lifecycle restore, rollback, derived navigation, or mode exit spans multiple reducers, choose one reducer/helper/state method as the owner and route other paths through it.
- In multi-stage UI callback flows, keep one canonical owner for visual cleanup and state reset instead of splitting ownership across intermediate success paths, teardown hooks, and reload paths.
- When earlier callbacks resolve critical context that later callbacks receive only partially, prefer carrying the resolved value forward explicitly over re-deriving it from weaker transient inputs.
- Do not reason from assumed ownership or remembered structure when the current code can be checked. Confirm owners, routes, dependencies, and test surface with reads/search/LSP before editing.
- When framework hit-testing or event context is known to be incomplete around nested subviews or transformed content, add a stable fallback that preserves the intended interaction contract.
- Preserve behavior parity across sibling coordinators, presenters, or adapters before introducing one-off exclusions in only one path.
- When mixed subview geometry can distort previews, hotspots, or interaction affordances, prefer representations aligned to the user's perceived whole interaction area.
- File-scope helper functions are acceptable for dense orchestrator-only handlers when extracting another reducer or type would not create a real boundary. Keep the helper narrow and avoid turning it into a shadow owner.
- Keep Voyager-specific heuristics here until they become stable enough to enforce repo-wide, then promote them into `.agents/rules/**`.
- Make bootstrap/onAppear flows idempotent via a flag (e.g., `didBootstrap`) to prevent double initialization when view lifecycle triggers multiple appearances.
- Normalize transient states at bootstrap — reset in-progress states (e.g., `connectInProgress` → `notVerified`, `disconnecting` → `disconnected`) to stable equivalents. Transient states from previous sessions should not persist across app launches.
- Keep transient process/UI states from becoming durable semantic state at restore, effect-completion, cancellation, teardown, and view-disappear boundaries. Convert them to stable state or discard them at the owning reducer boundary.
- Apply `@ObservableState` on the actual struct definition, not on a typealias. See `../../../../../rules/30-macos/02-tca-observation-lifecycle.md` for TCA observation patterns.
- For reducers, wrappers, and child features that can all reach the same persistence client, choose one persistence owner. Route other layers through actions or delegate events instead of saving the same durable state twice.
- When a feature defines delegate actions, every case should either be emitted by the reducer, consumed by a documented parent route, or removed. Reserved future delegate cases need a short Korean comment explaining the planned use.
- Extract time-based and fallback behavior into named policy values or small policy types before the values become migration points. Avoid inline TTL, grace-period, retry, or cache-window arithmetic in reducer logic.
- Keep fallback behavior intentionally narrow. A cached or synthetic success path should name the error categories that allow it; configuration, decoding, authorization, and invariant failures should normally surface rather than silently falling back.
- For cross-system contracts, add at least one test that decodes or resolves a real/captured fixture shape. Mocks that use the app's model names are not enough to prove API field names, URL keys, or config resolution.
- Use tiered config resolution for URL-like dependencies: feature-specific key first, shared base key second, neutral invalid fallback last. Never hardcode production URLs in dependency live values.
- Keep credential and snapshot persistence separate by data sensitivity. Tokens, refresh credentials, license secrets, and provider secrets belong in secure storage; status snapshots, expiry metadata, and non-sensitive cache state may use ordinary persistence.
- Prefer explicit action-chain observability for async results. If one handler should trigger another behavior, emit the downstream action with `.send(...)` unless there is a clear reason to keep the call private and unobservable.
- Mock-first implementation seams must name the live replacement condition near the seam. Do not let a synthetic client response look like verified live behavior.
- For foreground refresh or lifecycle refresh, prefer reducer-owned system observation plus signed-out no-op semantics over timer polling or view-owned service calls.

## Promotion test

- Keep a heuristic here while it is Voyager-specific, evolving, or mostly procedural.
- Move a heuristic into `.agents/rules/**` when it becomes a stable invariant that should apply automatically by path.
- When promoting a heuristic, rewrite it as a reusable rule. Do not carry forward issue IDs, exact type names, concrete file paths, or one-off ownership tables.

## Few-shot examples

- **Bad:** A success callback clears UI state, a teardown callback clears it again, and a reload helper also resets it "just in case."
  **Good:** Pick one canonical owner for cleanup and route the other paths through that owner or remove the duplicate reset.

- **Bad:** Validation resolves the correct destination early, but a later callback re-derives it from weaker transient data because the earlier value was not carried forward.
  **Good:** Preserve the resolved context explicitly across the callback chain.

- **Bad:** One coordinator adds a one-off exclusion to make a flaky interaction pass while sibling coordinators keep the original behavior.
  **Good:** Check sibling paths first and either preserve parity or document the intentional divergence.
