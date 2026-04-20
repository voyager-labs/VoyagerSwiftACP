# Spec, Contract, and Flow Review Guide

Use this guide when `feature-spec-checker` reviews one category's FEATURE_SPEC docs against `contracts/*.toml` and `flows/*.md`.

## Scope

This checker is narrower than bundle consistency.

It answers:

- do interaction specs use the same object terms as the contract?
- do interaction specs use the same state vocabulary as the contract?
- do interaction specs avoid contract-forbidden terms?
- do flow docs describe the same sequence and branch assumptions as the specs?

It does not answer:

- whether FI, IA, and FS tables all match each other
- whether a missing `structure_key` or stale frontmatter should be synced from inventory

## Deterministic pass

Start with `check_contract_consistency.py`.

That script already checks:

- unknown interactions referenced by a contract
- invalid transition state references
- missing spec contract references
- missing expected object terms in interaction specs
- missing expected state terms in interaction specs
- forbidden state terms still present in interaction specs

Treat `FAIL` as structural problems and `WARN` as review-relevant semantic drift.

## Lint pass

Run strict spec lint on interaction specs after the contract check.

Why:

- you still need the fixed section shell and frontmatter to be intact
- a spec with broken structure is not reliable enough for semantic contract review

## Flow review pass

Flow review is semantic even when the contract checker passes.

Check these explicitly:

### 1. Sequence alignment

- happy-path order in `flows/*.md` matches the order implied by linked interaction specs
- branch points such as cancel, retry, regenerate, and restore happen at the same step boundary

### 2. Object alignment

- the flow doc uses the same primary object names as the contract
- it does not introduce alternate names for the same object
- it does not blur object boundaries, for example treating `request`, `response`, and `turn` as interchangeable

### 3. State alignment

- the flow doc uses allowed state names from the contract
- the flow doc does not revive forbidden or stale state labels
- interaction specs and the flow doc describe the same transition boundary for each state

### 4. Trigger and ownership alignment

- the flow doc assigns actions to the same interaction that owns them in the contract
- interaction specs do not claim ownership of a transition that the contract gives to another interaction

### 5. Branch semantics

- cancel path, retry path, regenerate path, and session continuation path describe the same downstream effects across flow docs and interaction specs
- no doc says a branch creates, preserves, clears, or forks objects differently from the others unless that difference is explicitly intentional

## Common findings to surface

### `FAIL`

- flow links an interaction that does not exist
- a contract references an interaction that has no spec
- a spec depends on an unknown state term
- a transition names a state not declared by the contract

### `WARN`

- flow doc uses a stale synonym for a contract object
- flow doc implies a different order from the linked interaction specs
- interaction spec omits a contract-required state term
- interaction spec still mentions a contract-forbidden state term
- flow doc omits the branch consequence that the interaction spec declares

## Reporting rule

Do not collapse semantic drift into a vague statement like "looks mostly aligned."

Name the drift directly:

- which object or state term differs
- which interaction or flow step owns the behavior
- whether the disagreement changes implementation or review interpretation
