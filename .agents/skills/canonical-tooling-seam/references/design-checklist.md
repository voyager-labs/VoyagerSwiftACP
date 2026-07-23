# Canonical Tooling Seam Design Checklist

Use this reference after inventorying hosts and before changing commands. It keeps the seam narrow and gives each policy a single owner.

## Seam decision table

| Condition                                                              | Choose         | Why                                                           |
| ---------------------------------------------------------------------- | -------------- | ------------------------------------------------------------- |
| Hosts need native lifecycle control but share path and flag resolution | Resolver       | It returns one validated plan without replacing host control. |
| Setup, shared locks, execution, and cleanup must be atomic             | Wrapper        | One process can own lifecycle and shared state.               |
| A host has a different task schema or environment model                | Adapter        | It translates host inputs without owning policy.              |
| Only tool selection differs                                            | `code-tooling` | This is executor routing, not execution-path architecture.    |

## Ownership decision table

| Concern                                                   | Owner               | Acceptance condition                             |
| --------------------------------------------------------- | ------------------- | ------------------------------------------------ |
| Defaults, path resolution, cache identity                 | Resolver or wrapper | No host recomputes them.                         |
| Explicit request flags and approved environment overrides | Contract and caller | Precedence test proves preservation.             |
| IDE schema, CI variables, agent command syntax            | Adapter             | Adapter contains no duplicate defaults.          |
| Locks, active-run markers, run metadata                   | Shared-state owner  | Concurrent runs cannot corrupt shared state.     |
| Destructive cleanup                                       | Canonical seam      | Dry-run and containment checks precede mutation. |

## Contract checklist

- Define an operation allowlist and a versioned structured request/response shape.
- Carry arguments as arrays and environment as key/value entries.
- Represent local payload and shared cache as separate fields.
- Derive cache identity deterministically from compatibility inputs, not timestamps or host names.
- Preserve explicit overrides using documented precedence.
- Reject missing, malformed, unexpected, or path-escaping output. No direct-tool fallback.
- Use JSON or NUL-delimited transfer across process boundaries.

## Migration checklist

| Step                                | Evidence                                                           |
| ----------------------------------- | ------------------------------------------------------------------ |
| Inventory direct and indirect hosts | Table lists CLI, IDE, CI, agent, and legacy paths.                 |
| Select seam and assign owners       | Design names one owner per invariant.                              |
| Add adapters                        | Each host calls the seam, not the underlying tool.                 |
| Guard destructive behavior          | Dry-run, confirmation, containment, and symlink checks are tested. |
| Observe legacy use                  | A warning, metric, or failure identifies stale bypasses.           |
| Retire duplicates                   | No second owner remains for defaults, cache, locks, or metadata.   |

## Verification matrix

| Layer                       | Minimum proof                                                                         |
| --------------------------- | ------------------------------------------------------------------------------------- |
| Resolver/wrapper unit tests | Default derivation, explicit override, malformed contract, containment failure.       |
| Shared-state tests          | Deterministic cache identity, lock contention, active-run protection.                 |
| Host adapter tests          | CLI, IDE, CI, and agent inputs translate to the same canonical request.               |
| End-to-end tests            | Representative host commands execute through the seam and expose expected metadata.   |
| Migration checks            | Legacy bypass is absent, fails clearly, or emits intentional temporary observability. |

## Acceptance checklist

- [ ] Exactly one implementation owns every invariant policy.
- [ ] Explicit caller intent has higher precedence than resolver defaults.
- [ ] Malformed handoff data fails closed with an actionable error.
- [ ] Local payloads and shared cache state cannot be confused.
- [ ] Shared state has a lock and active-run protection where concurrent access is possible.
- [ ] Destructive actions are dry-run safe, contained, and never surprising.
- [ ] Each supported host has focused adapter evidence and one end-to-end path.
- [ ] Documentation points users to one canonical path and describes overrides.
