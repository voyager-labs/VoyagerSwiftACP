# Authority And State Contract

## Authority order

| Source | Decides | Does not decide |
| --- | --- | --- |
| Canonical product docs | product intent and acceptance criteria | Storybook implementation details |
| Native macOS source and deterministic captures | current implementation facts and rendered observations | future product intent |
| `apps/storybook/**` | inspectable React review states | product or runtime truth |
| Linear | ownership and work scope | visual or product correctness |

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
