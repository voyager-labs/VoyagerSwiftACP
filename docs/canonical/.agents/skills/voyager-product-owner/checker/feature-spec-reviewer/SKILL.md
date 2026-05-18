---
name: feature-spec-reviewer
description: "Review and validate Voyager FEATURE_SPEC interaction documents for a single feature_id against contracts, flows, and FI inventory at the semantic level. Use whenever the user asks to 점검, 검토, 검증, review, validate, or audit specific feature specs — especially when checking Observability adequacy, contract ownership compliance, Boundary Notes scope, Source section completeness, state vocabulary scope, or interaction-level duplication. Triggers: 스펙 점검, 스펙 검토, 검증해줘, ONB-002 점검, spec review, validate specs, 전반적인 검토. Do not use for FI/IA/FS bundle parity or contract/flow-only checks — use fi-ia-fs-consistency-checker or feature-spec-checker for those."
---

# Voyager Feature Spec Reviewer

Semantic review of interaction spec documents for a single feature_id, checking that each spec is internally consistent, contract-compliant, and scoped correctly.

## Why This Skill Exists

The existing checker skills cover:

- `feature-spec-checker`: deterministic contract/flow alignment (vocabulary, transitions, ownership declarations)
- `fi-ia-fs-consistency-checker`: cross-layer FI/IA/FS bundle parity (frontmatter sync, references, inventory matching)

Neither of them catches the kind of semantic issues that require reading the full spec body alongside the contract and making judgment calls:

- A display interaction's State Changes section says it writes to `progress_snapshot`, but the contract says `writes = []`
- An interaction's Boundary Notes claim status vocabulary that the feature doesn't own (e.g., `skipped` in a feature that has no skip flow)
- Observability sections copy-paste the same 5 items across unrelated interactions instead of owning interaction-specific checkpoints
- Source sections omit a category-level contract that the flow doc explicitly references

This skill fills that gap. It runs after deterministic checks are clean and applies human-judgment-level review to the spec body.

## Scope

Given one `feature_id` (e.g., `ONB-002`, `SET-007`), review all interaction specs under:

```
PRODUCT/05_FEATURE_SPECS/<category>/<feature_id>-<feature_slug>/*.md
```

Cross-reference against:

- `PRODUCT/05_FEATURE_SPECS/<category>/contracts/*.toml` — all contracts for the category
- `PRODUCT/05_FEATURE_SPECS/<category>/flows/*.md` — all flows for the category
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv` — FI interaction rows
- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv` — FI feature row

Required references:

- `references/review-checklist.md` — the full review checklist with examples

## When to Use

- User asks to review, validate, or audit a specific feature's specs
- User says 점검, 검토, 검증 for a feature_id's interaction specs
- After `feature-spec-checker` and `fi-ia-fs-consistency-checker` have passed and the user wants a deeper semantic pass
- Before marking specs as human-reviewed or removing `<<AI>>` markers

## When Not to Use

- FI/IA/FS bundle parity only → `fi-ia-fs-consistency-checker`
- Contract/flow alignment only → `feature-spec-checker`
- Drafting new specs → `feature-spec-author`
- Drafting new inventory rows → `feature-inventory-author`

## Workflow

### 1. Gather all source documents

Read in parallel:

- All interaction spec `.md` files for the target `feature_id`
- All category-level `contracts/*.toml`
- All category-level `flows/*.md`
- Matching FI rows from `INTERACTIONS/data.tsv` and `FEATURES/data.tsv`

### 2. Run deterministic checks first

If the user hasn't already run them, run the existing deterministic tools:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py <FEATURE_ID>
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py <CATEGORY>
find PRODUCT/05_FEATURE_SPECS/<category> -name '*.md' ! -path '*/flows/*' | xargs python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict
```

If these have failures, report them and stop — semantic review on structurally broken specs wastes effort.

### 3. Apply the semantic review checklist

Read `references/review-checklist.md` and apply each check to every interaction spec in the feature.

The checklist covers these areas:

1. **FI ↔ frontmatter alignment** — exact field matching (already partially covered by deterministic tools, but verify the deterministic pass is clean)
2. **Contract ownership compliance** — verify that each interaction's declared behavior (reads/writes in State Changes, Preconditions, Expected Outcome) does not exceed what the contract's `ownership` section grants
3. **State vocabulary scope** — verify that each interaction only references states it owns or transitions through, not the entire category vocabulary
4. **Observability adequacy** — check for interaction-specific checkpoints (not copy-pasted feature-level events), and that display/navigation interactions with no real observability needs use `-` instead of forced items
5. **Boundary Notes accuracy** — check that boundary claims match the actual ownership boundaries declared in contracts
6. **Source section completeness** — verify all relevant contracts and flows are listed, not just the parent session contract
7. **Interaction-level deduplication** — check that Observability, Expected Outcome, and State Changes are scoped to what this interaction owns, not the entire feature
8. **Section completeness** — verify the fixed section shell is present and no sections are accidentally missing
9. **Contract term precision** — verify spec prose uses exact contract-declared state names (`complete` not 완료), object keys (`access_status` not 접근 상태 결과), and policy values verbatim — no invented synonyms
10. **Style and tone compliance** — no vague hedge phrases (또는 동등한, 필요 시, 등), English UI labels verbatim (Next not 다음), English label forms in body prose over raw snake_case, no AI authoring artifacts
11. **Acceptance Criteria quality** — triple-clause pattern (상황에서, 하면, 해야 한다), one observable result per AC, exact state references in situation clauses

### 4. Report findings

Use this format:

```
## Review: <FEATURE_ID> — <Feature Name>

### ✅ Passed
- <item>: <brief note>

### ⚠️ Issues (WARN)
- <file>: <section> — <description of the issue>
  - Fix: <specific recommended change>

### ❌ Issues (FAIL)
- <file>: <section> — <description>
  - Fix: <specific recommended change>
```

Severity guide:

- **FAIL**: Contract violation (writes beyond ownership, forbidden states, missing required sections)
- **WARN**: Semantic drift (over-scoped vocabulary, copy-pasted observability, incomplete Source, imprecise terms, style violations)
- **Pass**: Clean or trivially acceptable

**Fix guide requirement**: Every finding must include a concrete fix with before/after text. Do not report issues without a recommended resolution.

### 5. If user asks for fixes, apply and re-validate

After applying fixes:

1. Re-run deterministic checks
2. Re-read the modified files
3. Verify the specific finding is resolved
4. Report the before/after

Do not batch-fix across features. Stay scoped to the requested `feature_id`.

## Output Principles

- Name the specific file, section, and line range for every finding
- For each issue, provide the exact recommended fix with before/after text, not just "this is wrong"
- Distinguish between contract violations (hard) and semantic/style improvements (soft)
- Do not collapse multiple distinct issues into one vague finding
- If the specs are clean, say so clearly — don't invent issues to justify the review
- When flagging a contract term precision issue, cite the exact contract section that defines the canonical term
- When flagging a style issue, cite the specific rule from the feature-spec writing guide

## Relationship to Other Skills

| Skill | What it catches | When to use |
|---|---|---|
| `feature-spec-checker` | Contract/flow vocabulary and structural alignment | Gate 2: deterministic pass |
| `fi-ia-fs-consistency-checker` | FI/IA/FS cross-layer parity | Gate 3: bundle validation |
| **`feature-spec-reviewer`** (this skill) | Semantic correctness within each interaction spec | Gate 2.5: after deterministic passes, before human review |
| `feature-spec-author` | Drafting new specs | Authoring phase |

## Example Prompts

- `ONB-002 스펙 전반적인 검토해줘`
- `ONB-001 interaction spec들 검증 진행해줘`
- `SET-007 스펙 점검하고 문제 있으면 수정까지 해줘`
- `ONB-003 스펙들이 contract랑 잘 맞는지, Observability도 적절한지 봐줘`
