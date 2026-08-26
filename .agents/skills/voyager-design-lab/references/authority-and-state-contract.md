# Authority And State Contract

## Authority order

| Source                                         | Decides                                                | Does not decide                  |
| ---------------------------------------------- | ------------------------------------------------------ | -------------------------------- |
| Canonical product docs                         | product intent and acceptance criteria                 | Storybook implementation details |
| Native macOS source and deterministic captures | current implementation facts and rendered observations | future product intent            |
| `apps/storybook/**`                            | inspectable React review states                        | product or runtime truth         |
| Linear                                         | ownership and work scope                               | visual or product correctness    |

## Independent-review contract

Use this only when a state has no root consumer. Every field is required; without all five, prefer an existing root composition or delete the state.

```md
## Review contract

- Question: What decision can this state resolve?
- Authority: Canonical source, native evidence, or `experiment`.
- Fixture: Named deterministic states and their inputs.
- Owner: Who accepts or rejects the decision?
- Retirement: Root consumer to integrate into, or date/condition for deletion.
```

A missing contract means the state is catalog debt, not coverage.

## Registry lifecycle

`surface-registry.ts` is the single source of truth for which surfaces are discoverable and their lifecycle. Each entry is discriminated on `lifecycle`:

- **`active`** — materialized and discovered; every story path field is set.
- **`planned`** — approved but not yet materialized; every path field is `null`.
- **`retired`** — formerly materialized; `story` is `null` and `retirementCondition` records why.

Add a surface by creating its registry entry (`planned` until stories exist), materialize by flipping to `active` with the story spec, and retire by setting `retired` with a condition. Never create a second surface inventory.

## Required root-consumer / null semantics

Every surface declares an explicit `rootConsumer` (the native host or composition that integrates it). Only `foundation` surfaces (shared tokens/primitives, e.g. `design-foundation`) may have `rootConsumer: null` — they have no single root consumer by design. A component surface with `rootConsumer: null` is an independent experiment that must carry a review contract and a retirement path; it is not a reusable specimen by default.

## DESIGN contract

Each materialized surface owns a `DESIGN.md` in its package that records the visual contract. The DESIGN document:

- Links the workspace root (`apps/storybook/DESIGN.md`) and the owning product intent rather than duplicating product truth.
- Names the surface's fixture owner and package root.
- Declares its catalog topology and any native-parity evidence (see `native-evidence-contract.md`).

## Owner, fixture owner, and retirement

- **Owner** — the product surface that accepts or rejects design decisions for the entry (`registry.owner`).
- **Fixture owner** — the party that owns the deterministic fixtures rendering the surface (`registry.fixtureOwner`); shared primitives are owned by `design-foundation`.
- **Retirement** — a surface or state is retired when its review question is resolved and it has no root consumer. Record the retirement in the registry (`lifecycle: "retired"` + `retirementCondition`) and in the review record.
