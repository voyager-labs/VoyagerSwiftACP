# Structure Validation

Use this document to keep `product-owner` structurally healthy.

## Design Goal

`product-owner` should stay thin.

It is an orchestration entrypoint that:

- decides when to delegate
- points to the stable project-scoped agents
- keeps the parent responsible for integration

It should not absorb the contents of author/reviewer skills.

## Required Structure

```text
product-owner/
├── SKILL.md
├── references/
│   ├── orchestration-workflow.md
│   ├── structure-validation.md
│   └── skill-map.md
└── evals/
    └── evals.json
```

## Invariants

- `SKILL.md` stays short and acts as the orchestration entrypoint only.
- detailed routing and delegation procedure lives in `references/orchestration-workflow.md`
- structure assumptions and validation criteria live in this file
- existing author/reviewer skills remain separate skills
- `.codex/agents/README.md` remains the routing source of truth

## Anti-patterns

- moving existing author/reviewer skills inside this skill directory
- duplicating the full behavior of `inventory_author`, `spec_author`, or `bundle_reviewer` inside `SKILL.md`
- turning this skill into a second source of truth for the project-scoped agent definitions
- growing `SKILL.md` into a long reference dump instead of keeping it as an entrypoint

## What To Check After Changes

- does `SKILL.md` still read like an orchestration entrypoint?
- do the reference files still exist and match the intent?
- is this skill still pointing outward to stable delegate surfaces instead of absorbing them?
- do the eval prompts still cover fuzzy requests, consistency review, and issue-drafting orchestration?
