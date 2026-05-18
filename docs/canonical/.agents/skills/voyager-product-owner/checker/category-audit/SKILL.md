---
name: category-audit
description: 'Run a multi-gate audit loop on an entire feature category (e.g., ONB, SET, RCL) in Voyager PRODUCT docs. Use when the user asks to audit, review, validate, or improve a whole category of specs — especially triggers like "ONB 스펙 점검", "카테고리 전체 검수", "audit this category", "full spec review for SET", or "이 카테고리 스펙들 완전 점검해줘". Also use when starting a new phase of work on a category and wanting a clean baseline before authoring begins.'
---

# Category Spec Audit Loop

Run a complete, repeatable audit on one feature category's interaction specifications.

Each gate is defined in a separate protocol file under `gates/`. Read the relevant gate file before executing that gate. The gate files contain the exact procedure, P/NP criteria, fix protocol, and expected commit format.

## Scope

- Target: one category_key (e.g., `ONB`, `SET`, `RCL`, `CBW`)
- Covers: all interaction specs under `PRODUCT/05_FEATURE_SPECS/<category>/`
- Cross-references: FI INTERACTIONS TSV, IA tables, contracts, flows, app implementation code

## Gate Execution Order

Execute gates **strictly in order**. Each gate produces a P/NP result. If NP, fix and re-run that gate before proceeding. After each gate PASS, commit before moving to the next gate.

```
Gate 0   → Scope & Baseline
Gate 0.5 → Source Availability
Gate 1   → Structural / Lint Safety Net
Gate 2   → Implementation Status + Phase Verification
Gate 3   → Contract / Flow / Vocab Alignment
Gate 4   → Blind Implementation-Readiness Review
Gate 5   → Semantic Reviewer Checklist
Gate 6   → Bundle / Category Parity
Final    → Category PASS
```

## Gate Protocol Files

| Gate | File | Purpose |
|---|---|---|
| 0 | `gates/g0-scope-and-baseline.md` | Define scope, list interaction_ids, snapshot baseline |
| 0.5 | `gates/g0.5-source-availability.md` | Verify all referenced artifacts exist |
| 1 | `gates/g1-structural-lint.md` | Deterministic lint pass on all category specs |
| 2 | `gates/g2-implementation-status.md` | Verify shipped/now status matches actual code |
| 3 | `gates/g3-contract-alignment.md` | Contract/flow/vocabulary alignment |
| 4 | `gates/g4-blind-clarity-review.md` | Independent agent clarity verification |
| 5 | `gates/g5-semantic-review.md` | 11-item semantic review checklist |
| 6 | `gates/g6-bundle-parity.md` | FI/IA/FS cross-layer parity |

## Execution Rules

1. **Read the gate file** before executing that gate. Each file contains the full procedure.
2. **One gate at a time.** Do not overlap gates.
3. **Fix before proceeding.** If a gate produces NP results, fix all NP items, re-run verification, then commit.
4. **Commit after each gate PASS.** Use the commit format specified in each gate file.
5. **Track progress** using the audit matrix (see `references/audit-matrix-template.md`).
6. **Partial progress is allowed.** Individual specs can PASS independently. The category PASS requires all in-scope specs to pass all gates.
7. **Intentional exclusions** must be explicitly marked as `out_of_scope` with a reason — never silently skip.

## Delegation Strategy

- **Gate 1, 3, 6**: Execute locally using deterministic scripts. No delegation needed.
- **Gate 2**: Requires app codebase access. Use `explore` agent for code verification if app code is in a separate repo.
- **Gate 4**: MUST use an independent subagent with no prior context. See gate file for the exact blind-review prompt.
- **Gate 5**: Use `feature-spec-reviewer` skill loaded into a subagent for each feature_id.

## Required References

- `gates/g0-scope-and-baseline.md` through `gates/g6-bundle-parity.md`
- `references/scoring-rubric.md`
- `references/audit-matrix-template.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/feature-spec-guide.md`
- `.agents/skills/voyager-product-owner/checker/feature-spec-reviewer/references/review-checklist.md`

## Relationship to Other Skills

- **product-owner (orchestrator)**: This skill is invoked as a lane in the orchestrator's routing. The orchestrator decides when to use it.
- **feature-spec-checker**: Gate 1 and 3 use this skill's scripts for deterministic checks.
- **feature-spec-reviewer**: Gate 5 delegates to this skill's checklist.
- **fi-ia-fs-consistency-checker**: Gate 6 uses this skill's bundle scripts.
- **feature-inventory-checker**: Gate 0 uses this skill for FI row validation.

## Output

After all gates pass, produce:

1. **Audit matrix**: completed matrix with all P marks (see template)
2. **Commit history**: one commit per gate, telling the audit story
3. **Summary**: brief report of findings, fixes applied, and any remaining Phase 2 items
4. **Category PASS declaration**: explicit statement that the category audit is complete

## Ralph Loop Integration

This skill is designed to run inside a ralph-loop for guaranteed completion. When invoked via ralph, the following structure applies.

### OKR Contract

Before the first gate, define this OKR:

- **Objective**: Category audit complete — all in-scope specs pass all gates
- **Metric**: `unresolved_np_count` = number of NP items across all gates
- **Target**: `unresolved_np_count = 0`
- **Verification commands**:
  ```bash
  python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict PRODUCT/05_FEATURE_SPECS/<category>/<category>-*/*.md
  python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/evaluate_category_consistency.py <CATEGORY>
  ```
- **Exit rule**: Ralph exits only when both verification commands produce 0 FAIL and the completed audit matrix has all cells marked P

### State Tracking

Use TODO list for gate-level progress (ralph reads this). Create TODO items at loop start:

```
[ ] Gate 0: Scope & Baseline — <CATEGORY>
[ ] Gate 0.5: Source Availability — <CATEGORY>
[ ] Gate 1: Structural Lint — <CATEGORY>
[ ] Gate 2: Implementation Status — <CATEGORY>
[ ] Gate 3: Contract Alignment — <CATEGORY>
[ ] Gate 4: Blind Clarity Review — <CATEGORY>
[ ] Gate 5: Semantic Review — <CATEGORY>
[ ] Gate 6: Bundle Parity — <CATEGORY>
[ ] Final: Category PASS declaration
```

### Iteration Mapping

Each ralph iteration = one gate cycle (execute → verify → fix if NP → commit on PASS):

| Ralph Phase | Audit Activity |
|---|---|
| `executing` | Running gate procedure, reading gate file, executing scripts or delegating agents |
| `verifying` | Running gate's verification command, checking P/NP criteria |
| `fixing` | Fixing NP items identified by the gate, re-running verification |
| On gate PASS | Commit with gate-specific format, mark TODO completed, advance to next gate |

### Start Condition

Ralph starts this skill when:
- User explicitly asks for a category audit with persistence ("돌려줘", "keep going until done", "ralph it")
- `/ralph-loop` or `ulw-loop` is invoked with a category audit prompt
- The orchestrator routes to this skill with a "full audit" request

### Stop Conditions

| Condition | Action |
|---|---|
| All gates PASS, audit matrix complete | Ralph exit — OKR met |
| Same NP item recurs 3+ times across iterations | Report as fundamental blocker, ask user |
| User says "stop" or "cancel" | Ralph cancel |
| Window exhausted but gates remain | Continue into next window |

### Evidence Requirements per Gate

Each gate must produce fresh evidence before declaring P:

| Gate | Evidence |
|---|---|
| 0 | FI row count matches spec file count (printed output) |
| 0.5 | All referenced files exist (grep/ls output) |
| 1 | `lint_feature_spec.py --strict` output: 0 FAIL |
| 2 | Code grep results confirming shipped/now status |
| 3 | `check_contract_consistency.py` output: 0 FAIL |
| 4 | Blind reviewer output: 0 critical ambiguities per spec |
| 5 | Review checklist output: all 11 items P per spec |
| 6 | `check_feature_bundle.py` output: 0 FAIL per feature_id |

### Architect Verification

After all gates pass:
- Tier: STANDARD
- Scope: all changed files in the audit branch
- Checklist: Final Checklist from SKILL.md + audit matrix completion

### Example Ralph Invocation

```
/ralph-loop ONB 카테고리 스펙 전체 점검해줘 — category-audit 스킬로 돌려
```

Or via orchestrator:
```
ONB 카테고리 전체 스펙 점검 완료될 때까지 돌려줘
```

## Example Prompts

- `ONB 카테고리 전체 스펙 점검해줘`
- `audit all SET specs with full gate loop`
- `RCL 스펙 카테고리 오디트 돌려줘`
- `이 카테고리 베이스라인 잡고 싶은데, 전체 점검 루프 한 번 돌려줘`
