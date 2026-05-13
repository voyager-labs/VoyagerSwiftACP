# Spec, Contract, and Flow Review Guide

Use this guide when `feature-spec-checker` reviews one category's FEATURE_SPEC docs against `contracts/*.toml` and `flows/*.md`.

This is the semantic and structural review guide for `Gate 2. FS local check` in the feature-spec authoring lifecycle.

## Scope

This checker is narrower than bundle consistency.

It answers:

- does every FEATURE_SPEC category with interaction specs have a category contract?
- does every FEATURE_SPEC category with interaction specs have a category flow?
- do interaction specs use the same object terms as the contract?
- do interaction specs use the same state vocabulary as the contract?
- do interaction specs avoid contract-forbidden terms?
- do flow docs describe the same sequence and branch assumptions as the specs?

It does not answer:

- whether FI, IA, and FS tables all match each other
- whether a missing `structure_key` or stale frontmatter should be synced from inventory

## Precedence Reminder

When reviewing one interaction spec, use this precedence order before raising style findings:

1. matching FI `INTERACTIONS` row truth
2. interaction-spec frontmatter exact-match fields
3. frontmatter `summary` wording preference
4. interaction-spec body prose wording preference
5. contract/flow wording preference

Implications:

- If a frontmatter `summary` matches the FI row but uses wording you would not choose for body prose, do not report that as drift by default.
- If a frontmatter `summary` uses preferred wording but no longer matches the FI row, treat that as a structural sync problem, not a style improvement.
- Review body prose wording separately from frontmatter sync fields.

## Deterministic pass

Start with `check_contract_consistency.py`.

That script already checks:

- missing `contracts/*.toml` for categories that contain interaction spec markdown
- missing `flows/*.md` for categories that contain interaction spec markdown
- missing `primary_object_key` migration or unknown `OBJECTS.key` references
- object-reference fields that incorrectly use `WINDOW_STRUCTURE.structure_key` values
- unknown region references in `display_region`, `scope_region`, or `control_region`
- unused contract vocabulary declarations
- contract vocabulary that redefines an `OBJECTS` key
- ownership object references that fall outside declared contract scope
- unknown interactions referenced by a contract
- invalid transition state references
- `entered_by` and transition trigger ownership mismatches
- `exits_to` and declared transitions that disagree
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

- category has interaction specs but no `contracts/*.toml`
- category has interaction specs but no `flows/*.md`
- flow links an interaction that does not exist
- a contract references an interaction that has no spec
- a contract uses a window, pane, sidebar, toolbar, field, list, or container key as an object reference
- a contract region field references a key that does not exist in `WINDOW_STRUCTURE`
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

Clear this gate before handing the bundle to cross-layer bundle validation or `Phase 2. Human Review`.
