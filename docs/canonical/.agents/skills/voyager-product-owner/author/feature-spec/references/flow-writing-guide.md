# Flow Writing Guide

Use this guide when authoring or refactoring category-level flow docs under `PRODUCT/05_FEATURE_SPECS/<category>/flows/*.md`.

## Goal

Flow docs are required companion artifacts for contract-driven FEATURE_SPEC categories.

Use them to:

- explain the end-to-end sequence across multiple interaction specs
- show branch boundaries such as cancel, retry, restore, regenerate, or session continuation
- keep one human-readable source for sequence semantics while contracts keep the machine-readable vocabulary

Do not use flow docs to replace:

- interaction specs for one `interaction_id`
- `contracts/*.toml` for shared object/state/transition definitions

## Required Companion Artifacts

Every category flow doc must be grounded in:

- at least one `contracts/*.toml` file in the same category
- the interaction spec files that the flow actually sequences

The flow doc must link both directly.

## Path And Naming

Path shape:

- `PRODUCT/05_FEATURE_SPECS/<category>/flows/<name>.md`

Naming rules:

- keep the filename in `snake_case`
- prefer one canonical flow per category unless multiple flows are truly needed for different user journeys
- if multiple flow docs exist, each one must declare a narrower scope in `Intent`

## Metadata Rule

Do not use YAML frontmatter for flow docs by default.

Keep flow docs as plain markdown and express metadata through:

- the H1 title
- `Contract References`
- `Interaction Coverage`
- `Source`

## Fixed Sections

Keep these sections in the body:

1. `Intent`
2. `Contract References`
3. `Interaction Coverage`
4. `Flow Overview`
5. `Happy Path`
6. `Alternate Paths`
7. `Boundary Notes`
8. `Source`

## Writing Rules

- Write body prose in Korean.
- Keep one flow doc scoped to one coherent user journey or lifecycle.
- Use exact object names and exact state names from the linked contract files.
- Link the interaction specs directly instead of mentioning only `interaction_id` in plain text.
- Keep the flow doc sequence-oriented. Do not restate the full contract vocabulary prose if the contract already defines it.
- Use `Flow Overview` to show the canonical sequence with a fenced mermaid diagram.
- Do not treat `flowchart LR` as mandatory. Choose the mermaid direction that fits the flow best.
- Use `Happy Path` for the default sequence only.
- Use `Alternate Paths` for meaningful branch semantics such as cancel, retry, regenerate, restore, and continuation.
- When a linked contract policy depends on a repeated action or branch term such as `submit`, `regenerate`, `retry`, or `restore`, define that term's sequence consequence explicitly in `Happy Path`, `Alternate Paths`, or `Boundary Notes` instead of leaving the policy key to imply the meaning.
- Do not require a separate mermaid diagram for every alternate path. Write alternate paths as prose by default, and add extra diagrams only when the branch logic is hard to read from prose alone.
- Use `Boundary Notes` to explain handoff rules, reset semantics, or branch consequences that reviewers might otherwise infer incorrectly.
- In `Source`, keep `Category:` as a simple metadata line and write `Related contracts:` as relative markdown links, not backticked filename literals.

## Contract Alignment Rules

The flow doc must:

- reference at least one contract file by relative markdown link
- use the same object and state vocabulary as the contract
- avoid forbidden or stale state labels from the contract
- describe branch semantics that agree with the linked interaction specs

If the contract is ambiguous, stop and fix the contract first instead of smoothing the flow prose with near-synonyms.

## Interaction Coverage Rules

The flow doc must:

- link every interaction spec that materially owns a step in the sequence
- avoid claiming that one interaction owns a transition that another interaction spec actually owns
- make branch handoffs explicit when the path leaves one interaction and re-enters another

## Review Checklist

Before finishing, ask:

- does this flow link the current contract files directly?
- does this flow link the interaction specs it depends on?
- does the `Source` section list related contracts as markdown links instead of code-style filenames?
- does the happy path order match the linked specs?
- do alternate paths preserve the same object/state semantics as the contract?
- would a reviewer understand sequence ownership without reading implementation code?
