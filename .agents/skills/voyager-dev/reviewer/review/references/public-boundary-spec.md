# Voyager Dev Public Boundary Spec

## Goal

Make slice boundaries explicit so future package extraction, reuse, and same-layer collaboration stay predictable.

## Public boundary rules

- Every slice should expose a stable surface for other layers or slices to compose against.
- Do not reach into another slice's incidental helpers, nested decomposition files, or internal-only glue.
- In Swift terms, prefer stable top-level types, package/module entrypoints, and narrow adapter types as the slice boundary.
- Avoid broad re-export or "everything is public" patterns that blur ownership.

## Deep import rules

- Do not depend on another slice's internal file knowledge when a stable boundary should exist.
- Same-layer collaboration must not casually import peer internals; compose upward in `Pages` or `App` instead.
- Within the same slice, prefer direct local paths and explicit types over slice-wide barrel-style re-export patterns that hide circular structure.

## Entity cross-reference exception

- If one entity must reference another entity, keep that boundary narrow and explicit.
- Prefer a dedicated entity-to-entity bridge surface rather than importing arbitrary internals from a peer entity.
- Treat entity cross-reference as an exception to justify, not a default collaboration style.

## Package extraction posture

- Ask whether this slice already has a stable enough boundary to become a package target later.
- If the answer depends on internal file knowledge or same-layer shortcuts, the boundary is not ready yet.

## Common boundary expansion triggers

Swift 6 migration tends to inflate public surfaces. Watch for these patterns:

- **Nested action enums in public parent enums.** Swift 6 requires associated value types in public enums to be at least as visible as the enum itself. If a public enum has cases like `case view(View)`, the `View` nested type must be public. This is a compiler requirement, not a style choice. Do NOT flag these as unjustified expansion. The nested type can be internal only when the parent enum is also internal, or when the nested type is never used as a case associated value.
- **Protocol witness methods on public classes.** A `public final class` conforming to a `public protocol` requires the conformance methods to be public. This applies even for ObjC-dispatched protocols like NSWindowDelegate. Swift 6's type checker enforces visibility consistency regardless of the dispatch mechanism.
- **`@preconcurrency import` and `@unchecked Sendable`** address concurrency concerns without expanding the public boundary. Prefer these over promoting internal types to public solely for Sendable compliance.

## Review checks

- Would another slice know what to import without reading internal files?
- Is same-layer collaboration composed upward instead of sideways?
- Is the boundary narrow enough to survive package extraction?
- When public visibility was added during Swift 6 migration, is it a compiler requirement (associated value type in public enum, protocol witness on public class) or an unjustified expansion?
