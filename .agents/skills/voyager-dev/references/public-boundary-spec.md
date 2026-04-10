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

## Review checks

- Would another slice know what to import without reading internal files?
- Is same-layer collaboration composed upward instead of sideways?
- Is the boundary narrow enough to survive package extraction?
