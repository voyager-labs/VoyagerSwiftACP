# Gate 5: Semantic Review

## Input

- Category scope manifest (from Gate 0)
- All interaction spec files that passed Gate 4
- Category contracts (`contracts/*.toml`)
- Category flows (`flows/*.md`)
- FI INTERACTIONS rows
- `review-checklist.md` from feature-spec-reviewer skill

## Purpose

Catch semantic issues that deterministic checks and blind review cannot: ownership boundary violations, state vocabulary drift, observability gaps, tone/style problems, and interaction-level duplication. This is the human-quality review layer.

## Procedure

### 1. Load the review checklist

Read `.agents/skills/voyager-product-owner/checker/feature-spec-reviewer/references/review-checklist.md`. This defines 11 review areas.

### 2. Execute per feature_id

For each feature_id in scope (not per interaction — group interactions by feature):

1. Gather all related docs:
   - All interaction specs for this feature_id
   - Category contract(s)
   - Category flow(s)
   - FI INTERACTIONS rows
2. Run the 11-item review:

| # | Review Area | What to Check |
|---|---|---|
| 1 | FI/frontmatter alignment | Already verified in Gate 1 — skip unless new edits |
| 2 | Contract ownership compliance | `reads`/`writes` in prose match contract ownership |
| 3 | State vocabulary scope | All state names exist in contract vocabulary |
| 4 | Observability adequacy | Analytics section covers key events, not just happy path |
| 5 | Boundary note accuracy | Boundary notes correctly define what interaction does NOT do |
| 6 | Source completeness | Inventory row, Contracts, Flows all present and correct |
| 7 | Interaction-level deduplication | No two specs claim the same action/state change |
| 8 | Section completeness/order | All required sections present in correct order |
| 9 | Contract term precision | Prose uses exact contract keys, not synonyms |
| 10 | Style/tone/AI-artifact | No `<<AI>>` markers in prose (only in summary), no vague hedging |
| 11 | Acceptance criteria quality | AC follows triple-clause pattern, each is testable |

### 3. Delegation strategy

- Use `feature-spec-reviewer` skill loaded into a subagent for each feature_id
- Run feature_ids in parallel (up to 3 simultaneous)
- Each subagent receives: the review checklist, all relevant docs, and the category contracts/flows

### 4. Report format

For each feature_id, produce:

```
feature_id: ONB-002
review_items:
  - area: "Contract ownership compliance"
    status: P
    note: "display interaction correctly does not claim writes"
  - area: "Observability adequacy"
    status: NP
    note: "missing analytics for beta access check failure"
    fix: "Add failure event to Observability section of ONB-002-show_access_unlock_status.md"
```

## P Criteria

- All 11 review areas are P for every in-scope feature_id
- No unresolved semantic contradictions between specs

## NP Criteria

- Any review area is NP for any feature_id
- Two specs claim ownership of the same state change
- Contract vocabulary drift detected (prose uses terms not in contracts)
- Observability section missing critical events

## Fix Protocol

For each NP item:

1. Read the reviewer's fix recommendation
2. Make the minimum edit that resolves the issue
3. Re-run only the affected review area (not all 11)
4. If still NP after 2 attempts, flag as "needs product decision"

## Commit Format

```
audit(<CATEGORY>): Gate 5 — 시맨틱 리뷰 (<count>P, <count>NP)
```

If fixes were applied:

```
audit(<CATEGORY>): Gate 5 — 시맨틱 이슈 해소 (<count>건 수정, 전면 P)
```

## Output

- Per-feature review results with 11-item breakdown
- List of all fixes applied
- Updated audit matrix with Gate 5 column filled
