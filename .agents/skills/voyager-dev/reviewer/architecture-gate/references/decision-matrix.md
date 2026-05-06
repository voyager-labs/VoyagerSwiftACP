# Voyager Dev Reuse Decision Matrix

## Scoring model

`Reuse Score = Similarity + LayerFit + Testability - CouplingRisk - WrapperTax`

- `Similarity` (0-4)
    - Signature/behavior parity with target
- `LayerFit` (0-3)
    - Resides in correct FSD layer and segment
- `Testability` (0-2)
    - Existing tests or easy `TestStore` coverage
- `CouplingRisk` (0-3)
    - Hidden dependencies, side effects, cross-layer leaks
- `WrapperTax` (0-3)
    - Penalize new types that only mirror existing state/behavior or add compatibility shells without owning a real boundary

## Decision thresholds

- `>= 6`: `extend` or `reuse`
- `4-5`: `adapt` only if the adapter owns real translation, migration, or boundary protection
- `<= 3`: `new` only if the scope is large enough to justify a new named responsibility

## Output contract

For final implementation planning, always emit:

1. `reuse-candidates`
    - ranked table with score and rationale
2. `architecture-risks`
    - gate failures and mitigation
3. `final-choice`
    - `extend` | `reuse` | `adapt` | `new` + reason
4. `implementation-delta`
    - files to change, symbols to touch, verification commands

## Rule

Default is not `new`. Prefer extending an existing type first, then direct reuse.
Choose `new` only when reusable candidates fail score or architecture gates, and the new scope has a strong enough independent responsibility to stay understandable.
