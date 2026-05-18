# Gate 4: Blind Implementation-Readiness Review

## Input

- Category scope manifest (from Gate 0)
- All interaction spec files for the category
- Referenced contract excerpts (from `contracts/*.toml`)
- Referenced flow excerpts (from `flows/*.md`)
- FI INTERACTIONS rows for each spec
- Vocabulary/state definitions from contracts

## Purpose

Determine whether an engineer with **no prior product context** could implement and test each interaction from the spec alone. This gate catches ambiguities that deterministic lint and contract checks cannot detect — missing business rules, underspecified behavior, conflicting terminology, and implicit assumptions.

## Procedure

### 1. Spawn independent blind reviewer(s)

For each spec in scope, spawn a **fresh subagent** with no session context about Voyager.

The subagent receives ONLY:
- The spec markdown file
- Contract excerpts referenced in the spec's Source section
- Flow excerpts referenced in the spec's Source section
- The FI INTERACTIONS row for this interaction

The subagent does NOT receive:
- Any conversation history
- The app codebase
- Other specs in the category
- Any prior gate results

### 2. Blind reviewer prompt

Use this exact prompt for the blind reviewer:

```markdown
You are reviewing one interaction specification with no product context beyond the provided files.

Goal:
Determine whether an engineer could implement and test this interaction from the spec alone.

Inputs:
- Feature spec markdown (provided below)
- Referenced contract excerpts (provided below)
- Referenced flow excerpts (provided below)
- FI row for this interaction (provided below)

Rules:
- Do not infer product behavior not stated in the provided materials.
- If something is not explicit, list it as an assumption.
- Do not propose improvements unless they resolve a specific ambiguity.
- Use only P/NP scoring based on the rubric below.

Output:

## Implementation extraction
- User trigger:
- Preconditions:
- State read:
- State written:
- API / command / persistence expectations:
- UI feedback:
- Error / empty / loading states:
- Analytics / observability:
- Completion condition:

## Test cases
Write Given/When/Then cases only for behavior explicitly supported by the spec.

## Assumptions
List every assumption required to implement or test this interaction.

## Critical ambiguities
List only ambiguities that block implementation or test writing.

## Score
P if there are zero critical ambiguities.
NP if there is one or more critical ambiguity.

## Required fixes
For each NP item, name the missing spec decision and the section where it should be clarified.
```

### 3. Execute per spec

Run one blind reviewer per spec. For categories with many specs, run in parallel (up to 3 simultaneous subagents).

### 4. Aggregate results

After all blind reviews complete, produce a per-spec P/NP summary:

```
| spec | P/NP | critical_ambiguity_count | assumptions_count |
|------|------|--------------------------|-------------------|
| ONB-001-start... | P | 0 | 3 |
| ONB-002-show... | NP | 2 | 5 |
```

## P Criteria

All of the following must be true:

- Trigger and user intent are clear
- Preconditions are explicit and complete
- Primary success path is deterministic (no invented business rules needed)
- Required state reads/writes are explicit or clearly marked out of scope
- Contract/API/event ownership is unambiguous
- User-visible feedback is specified
- Error/empty/loading states are either specified or explicitly N/A
- Given/When/Then tests can be written without inventing behavior
- `[now]`, `[next]`, `[later]` content is not mixed ambiguously within the same section

## NP Criteria

Any of the following is sufficient:

- Reviewer must invent a business rule to write tests
- Reviewer cannot determine whether behavior is current or planned
- Spec implies a write/action but ownership contract does not support it
- Acceptance criteria lack observable outcome (test-shaped but unverifiable)
- State names, object names, or CTA labels conflict with contract/FI/IA
- Error or edge behavior affects implementation but is absent from spec
- Multiple specs appear to own the same interaction outcome
- `[now]` and `[next]` markers appear in the same bullet or paragraph without clear separation

## Fix Protocol

For each NP item:

1. Read the blind reviewer's "Required fixes" section
2. Identify which spec section needs clarification
3. Make the minimum edit that resolves the ambiguity — do not rewrite the whole spec
4. Re-run the blind reviewer on the fixed spec only
5. If still NP after 2 fix attempts, flag as "needs product decision" and document the open question

## Commit Format

```
audit(<CATEGORY>): Gate 4 — 명확성 검증 P/NP (<count>P, <count>NP)
```

If fixes were applied:

```
audit(<CATEGORY>): Gate 4 — 모호성 해소 (<count>건 수정, 전면 P)
```

## Output

- Per-spec blind review results
- Aggregate P/NP summary table
- List of all assumptions across specs (for future spec improvement reference)
- Updated audit matrix with Gate 4 column filled
