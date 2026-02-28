# Voyager Dev Reuse Decision Matrix

## Scoring model

`Reuse Score = Similarity + LayerFit + Testability - CouplingRisk`

- `Similarity` (0-4)
  - Signature/behavior parity with target
- `LayerFit` (0-3)
  - Resides in correct FSD layer and segment
- `Testability` (0-2)
  - Existing tests or easy `TestStore` coverage
- `CouplingRisk` (0-3)
  - Hidden dependencies, side effects, cross-layer leaks

## Decision thresholds

- `>= 5`: `reuse`
- `3-4`: `adapt` (wrapper/adapter)
- `<= 2`: `new`

## Output contract

For final implementation planning, always emit:

1. `reuse-candidates`
   - ranked table with score and rationale
2. `architecture-risks`
   - gate failures and mitigation
3. `final-choice`
   - `reuse` | `adapt` | `new` + reason
4. `implementation-delta`
   - files to change, symbols to touch, verification commands

## Rule

Default is not `new`. Choose `new` only when all reusable candidates fail score or architecture gates.
