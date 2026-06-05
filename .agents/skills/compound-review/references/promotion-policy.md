# Promotion Heuristics and Conflict-Detection Policy

**Version:** 1.0
**Scope:** Defines when compound-review outputs (findings, learnings, skill-drafts) are strong enough to promote into `.agents/` governance artifacts. Governs Stage 2 → Stage 3 handoff decisions in `lifecycle-contract.md`.
**Source of truth for:** All agents and human operators who consume compound-review outputs and decide whether to adopt, extend, or leave them local-only.
**Normative references:** `evidence-trust-taxonomy.md`, `lifecycle-contract.md`, `findings-schema.md`, `learning-schema.md`, `skill-draft-schema.md`

---

## 1. Purpose

Not every compound-review finding deserves promotion to a global rule or skill. A single-run anecdote may reflect one-off context. A recurring pattern across multiple authoritative runs carries stronger signal. This policy provides deterministic criteria for three promotion decisions:

1. **Reinforce existing** — extend an already-adopted rule/skill with new guidance.
2. **Create new** — adopt a new rule or skill into `.agents/`.
3. **Stay local-only** — keep the finding in `.sisyphus/` without promoting.

The policy also defines conflict detection to prevent duplicate or contradictory targets.

---

## 2. Definitions

| Term                  | Definition                                                                                                           |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **Promotion**         | Moving a compound-review output from `.sisyphus/` into `.agents/` as a committed rule, skill, or reference document. |
| **Recurrence**        | The same finding (by `dedupe_key` or category/tag overlap) appearing across multiple authoritative runs.             |
| **Authoritative run** | A compound-review run classified as `authoritative` per `evidence-trust-taxonomy.md` §2.1.                           |
| **Adopted artifact**  | A rule or skill that has already been committed to `.agents/` (Stage 3 complete).                                    |
| **Target**            | The file path in `.agents/` that a promotion proposes to create or modify.                                           |
| **Local-only**        | Artifacts that remain in `.sisyphus/` and are never promoted to `.agents/`.                                          |

---

## 3. Minimum Recurrence Threshold

### 3.1 Rule: ≥2 Authoritative Runs Required for Promotion

A finding or learning entry may only be promoted to a **new** `.agents/` rule or skill when it has been observed in **at least two (2) independent authoritative runs**.

**What counts as independent:**

| Source combination                                  | Independent?        | Rationale                                                                                              |
| --------------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------ |
| Same `plan_slug`, different `run_id`                | Yes                 | Different evidence snapshots, possibly different facets consumed.                                      |
| Different `plan_slug`, same tags/category           | Yes (stronger)      | Cross-plan recurrence is the strongest signal.                                                         |
| Same `plan_slug`, same `run_id`, different findings | No                  | Same evidence substrate; not independent.                                                              |
| One authoritative run + one reference-only run      | Partial (score 1.5) | Reference-only corroborates but does not carry full weight. Must pair with at least one authoritative. |

### 3.2 How to Count Recurrence

1. Scan all `findings.json` files across `.sisyphus/reviews/` for matching `dedupe_key` values.
2. Cross-reference `learning.md` files for matching `category` + `tags` overlap (≥2 tags in common).
3. Each unique `(plan_slug, run_id)` pair with the finding in an authoritative run counts as **1**.
4. A finding appearing in 2+ findings.json AND 1+ learning.md across independent runs counts as **2** (stronger than 2 findings from same plan only).

### 3.3 Exceptions to Recurrence Threshold

The recurrence threshold may be waived only by explicit operator override with documented rationale:

| Exception         | Condition                                                               | Evidence required                                                                               |
| ----------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Operator override | Operator explicitly requests promotion after single run                 | Written note in adoption commit explaining why recurrence is not needed                         |
| Critical severity | Finding is `critical` severity with `verdict: REJECT` and no workaround | Must still be paired with human review — promotion is emergency hotfix, not standard governance |

Single-run anecdotes without operator override or critical severity **cannot** promote. No exceptions.

---

## 4. Confidence Downgrade Path

### 4.1 Confidence Scoring for Promotion Eligibility

Building on the confidence scoring matrix in `evidence-trust-taxonomy.md` §6.3, a **promotion confidence score** is calculated per finding or learning entry:

| Signal                                                         | Points     |
| -------------------------------------------------------------- | ---------- |
| Each independent authoritative run containing the finding      | +2         |
| Cross-plan recurrence (different `plan_slug`)                  | +1 (bonus) |
| Finding confirmed by multiple facets in a single run           | +1         |
| Finding reaffirmed across runs with same verdict               | +1         |
| Learning entry present in `learning.md` (synthesized, not raw) | +1         |
| Skill-draft exists for the finding                             | +1         |

| Penalty                                            | Points                            |
| -------------------------------------------------- | --------------------------------- |
| Source run is `reference-only` (not authoritative) | -2                                |
| Source run has `confidence_reduced: true`          | -1                                |
| Finding verdict flipped between runs               | -2 (investigate before promoting) |
| Only one evidence file in source run               | -1                                |

### 4.2 Promotion Thresholds

| Promotion action               | Minimum score            | Additional requirements                                                            |
| ------------------------------ | ------------------------ | ---------------------------------------------------------------------------------- |
| **Create new rule/skill**      | ≥5                       | ≥2 independent authoritative runs; no verdict flip; no critical confidence penalty |
| **Extend existing rule/skill** | ≥3                       | ≥1 authoritative run; existing target has non-overlapping scope                    |
| **Stay local-only**            | <3 or fails requirements | Artifact remains in `.sisyphus/`                                                   |

### 4.3 Stale and Reference-Only Evidence

Findings sourced exclusively from `reference-only` or `invalid` runs cannot promote, regardless of score. Reference-only evidence may **corroborate** an authoritative finding (adding points) but cannot serve as the sole basis for promotion.

| Evidence trust class | Promotion role                                                                          |
| -------------------- | --------------------------------------------------------------------------------------- |
| `authoritative`      | Primary basis. Can promote alone if threshold met.                                      |
| `reference-only`     | Corroboration only. Adds +1 point when paired with authoritative. Cannot promote alone. |
| `invalid`            | No role. Ignored for promotion scoring.                                                 |

### 4.4 Confidence Downgrade Sequence

When evaluating whether a promotion is still valid after time has passed:

1. Check whether newer authoritative runs exist for the same `dedupe_key`.
2. If newer runs contradict the finding (verdict flip, reduced severity), downgrade promotion confidence by -3.
3. If newer runs reaffirm the finding, confidence is stable — no downgrade.
4. If no newer runs exist, the original confidence holds but the operator should be informed that the finding has not been re-confirmed recently.

---

## 5. Extend Existing vs. Create New Decision Rule

### 5.1 Deterministic Rule

Apply this decision tree **in order**. The first matching condition determines the action:

```
1. Does an adopted artifact in .agents/ already address the same dedupe_key or category?
   ├── YES → Is the overlap partial (same category, different specific issue)?
   │         ├── YES → EXTEND the existing artifact with a new section or entry
   │         └── NO  → The existing artifact already covers this. STAY LOCAL-ONLY.
   └── NO → Continue to step 2.

2. Does an adopted artifact in .agents/ have ≥2 tags in common with the finding?
   ├── YES → Could the finding be expressed as an additional section in that artifact?
   │         ├── YES → EXTEND the existing artifact.
   │         └── NO  → Continue to step 3.
   └── NO → Continue to step 3.

3. Does the finding propose a target path that already exists in .agents/?
   ├── YES → EXTEND (the file exists and should be updated, not duplicated).
   └── NO  → CREATE NEW (no existing artifact covers this domain).

4. Is this a single-run observation with no recurrence?
   └── YES → STAY LOCAL-ONLY regardless of other factors.
```

### 5.2 Extend Requirements

When extending an existing artifact:

| Requirement                                                                                          | Rationale                                 |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| The extension must be additive — do not modify or remove existing sections without operator approval | Preserves existing governance commitments |
| Add a `## {Category}: {subtopic}` section rather than modifying existing prose                       | Clear provenance for each addition        |
| Record the source `run_id` and `dedupe_key` in the new section                                       | Lineage for future audits                 |
| The extended artifact must still pass its own verification criteria                                  | No regression in existing guarantees      |

### 5.3 Create New Requirements

When creating a new artifact:

| Requirement                                                      | Rationale                                                |
| ---------------------------------------------------------------- | -------------------------------------------------------- |
| Must pass the ≥2 recurrence threshold (§3.1)                     | Prevents single-run anecdotes from becoming global rules |
| Must pass the ≥5 promotion confidence score (§4.2)               | Ensures sufficient evidence backing                      |
| Must pass duplicate-target conflict check (§6)                   | Prevents duplication                                     |
| Must have a `Target File` path that does not exist in `.agents/` | New creation, not extension                              |
| Operator must approve before adoption (Stage 3)                  | Human gate per `lifecycle-contract.md`                   |

---

## 6. Duplicate-Target Conflict Check

### 6.1 Purpose

Before creating or extending a target, verify that the proposed change does not duplicate or contradict existing content in `.agents/`.

### 6.2 Conflict Detection Algorithm

1. **Exact path check:** Does the proposed `Target File` path already exist?
    - If YES: This is an extension scenario, not a new creation. Apply §5.2.
2. **Semantic overlap check:** Search all files in `.agents/rules/` and `.agents/skills/` for:
    - Matching `dedupe_key` values in any content.
    - Matching `category` headings.
    - Overlapping `tags` (≥2 tags in common with any existing artifact).
3. **Cross-reference with adopted exemplars:** Compare the proposed finding's `Applies when` conditions against existing rules' `Applies when` sections. If the conditions substantially overlap (≥50% of conditions match), the new proposal is likely a duplicate.

4. **Tag-based similarity search:** For each tag in the finding's `Tags` array, search for that tag across `.agents/`. If 3+ tags produce matches in the same existing artifact, flag as potential duplicate.

### 6.3 Conflict Resolution

| Conflict type                                                       | Resolution                                                                                                         |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Exact duplicate (same dedupe_key, same category, same applies-when) | Do NOT create. Stay local-only. Existing artifact already covers this.                                             |
| Partial overlap (same category, different applies-when)             | EXTEND existing with new section. Do NOT create parallel artifact.                                                 |
| Domain overlap (shared tags, different category)                    | May CREATE NEW if the domain is genuinely distinct. Document why extension is insufficient in the draft rationale. |
| No overlap found                                                    | CREATE NEW. No conflict.                                                                                           |

### 6.4 Conflict Check Exclusions

The conflict check does **not** apply to:

- `reference-only` artifacts in `.sisyphus/` (they are not adopted governance).
- Malformed or `invalid` artifacts.
- Artifacts outside `.agents/` (e.g., `docs/` or `apps/`).

---

## 7. Blocking Conditions

These conditions unconditionally block promotion regardless of score or recurrence:

| Blocker                                                              | Rationale                                                                          |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Single-run anecdote (recurrence = 1) with no operator override       | One observation is not a pattern.                                                  |
| Source run is `reference-only` or `invalid`                          | Cannot base governance on non-authoritative evidence.                              |
| Finding verdict flipped across runs with no resolution               | Conflicting evidence — the issue needs investigation, not promotion.               |
| Duplicate-target conflict with no extension path                     | Two rules for the same domain creates confusion.                                   |
| Source findings are exclusively `informational` severity             | Informational findings document observations, not actionable governance.           |
| `confidence_reduced: true` with 2+ missing facets in all source runs | The review coverage is too incomplete to justify promotion.                        |
| No `learning.md` entry exists for the finding                        | Findings alone are raw observations; learning synthesis is required for promotion. |

---

## 8. Promotion Decision Summary Table

| Condition                                                             | Action                            |
| --------------------------------------------------------------------- | --------------------------------- |
| Recurrence ≥2, score ≥5, no conflict, learning exists                 | **CREATE NEW**                    |
| Recurrence ≥1, score ≥3, existing target found, non-overlapping scope | **EXTEND EXISTING**               |
| Recurrence ≥2, score ≥5, partial overlap found                        | **EXTEND EXISTING** (add section) |
| Recurrence = 1, no operator override                                  | **STAY LOCAL-ONLY**               |
| Source is reference-only or invalid                                   | **STAY LOCAL-ONLY**               |
| Verdict flipped across runs                                           | **STAY LOCAL-ONLY** (investigate) |
| Duplicate-target with no extension path                               | **STAY LOCAL-ONLY**               |
| Score < 3                                                             | **STAY LOCAL-ONLY**               |

---

## 9. Worked Examples

### 9.1 Exemplar 1: Scope-Diff Isolation → Adopted as `05-scope-diff-isolation.md`

**Source findings:**

- VOY-225, run 2026-04-16-133347: `FIND-001` (`voy-225-scope-diff-not-isolated`), severity `high`, verdict `APPROVE`
- VOY-226, run 2026-04-16-133347: `FIND-001` (`voy-226-scope-diff-not-isolated`), severity `high`, verdict `APPROVE`
- VOY-226, run 2026-04-16-052652: same category/tags recurrence

**Recurrence check:**

- Independent runs: 3 (VOY-225 run 133347, VOY-226 run 052652, VOY-226 run 133347)
- Cross-plan recurrence: YES (VOY-225 and VOY-226 are different plan_slugs)
- Threshold: ≥2 → **PASS** (3 independent runs)

**Confidence score:**

- 3 independent authoritative runs × +2 = +6
- Cross-plan recurrence bonus = +1
- Learning entries present = +1
- Total = **8** (threshold ≥5 → **PASS**)

**Conflict check:**

- No existing `.agents/` artifact addressed scope-diff isolation at time of adoption.
- No dedupe_key match, no tag overlap with existing rules.
- **No conflict** → CREATE NEW.

**Decision:** CREATE NEW → `.agents/rules/99-agent/04-scope-diff-isolation.md` ✅

### 9.2 Exemplar 2: Xcode Test-Plan Visibility → Adopted as `04-xcode-test-plan-visibility.md`

**Source findings:**

- VOY-226, run 2026-04-16-052652: `FIND-002` (`voy-226-spm-cli-test-exclusion`), severity `high`
- VOY-226, run 2026-04-16-133347: `FIND-002` (`voy-226-spm-cli-test-exclusion`), severity `high`
- Both runs: identical tags `test-execution, xcode-cli, spm-package-tests, test-plan-configuration`

**Recurrence check:**

- Independent runs: 2 (same plan, different run_ids)
- Cross-plan: NO (both VOY-226)
- Threshold: ≥2 → **PASS** (2 independent runs)

**Confidence score:**

- 2 independent authoritative runs × +2 = +4
- Learning entries present = +1
- Multiple facets confirmed = +1
- Total = **6** (threshold ≥5 → **PASS**)

**Conflict check:**

- No existing `.agents/` artifact addressed SPM test-plan visibility.
- Tags partially overlap with scope-diff rule but domain is distinct.
- **No conflict** → CREATE NEW.

**Decision:** CREATE NEW → `.agents/rules/30-macos/04-xcode-test-plan-visibility.md` ✅

### 9.3 Counter-Example: Single-Run Anecdote Blocked

**Hypothetical:** A finding about "reducer naming convention" appears only in VOY-225 run 2026-04-16-133347.

**Recurrence check:**

- Independent runs: 1
- Threshold: ≥2 → **FAIL**

**Decision:** STAY LOCAL-ONLY. No promotion regardless of severity or score.

### 9.4 Counter-Example: Reference-Only Cannot Promote Alone

**Hypothetical:** A finding about "worktree branch naming" appears only in a reference-only earlier run of VOY-226.

**Trust class check:**

- Source run is `reference-only` (superseded by newer authoritative run).
- Per §4.3, reference-only cannot promote alone.

**Decision:** STAY LOCAL-ONLY. Reference-only may corroborate but not serve as sole basis.

---

## 10. Relationship to Other Reference Documents

| Reference                    | Relationship                                                                                                                   |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `evidence-trust-taxonomy.md` | Defines trust classes used in §4.3 and blocking conditions. The confidence scoring matrix in §4.1 extends the taxonomy's §6.3. |
| `lifecycle-contract.md`      | Defines Stage 2 → Stage 3 handoff. This policy governns the decision at that handoff point.                                    |
| `findings-schema.md`         | Defines the `dedupe_key`, `severity`, `verdict` fields used for recurrence counting and conflict detection.                    |
| `learning-schema.md`         | Defines the learning entry structure. Presence of a learning entry is required for promotion (§7).                             |
| `skill-draft-schema.md`      | Defines the draft structure and threshold. Draft existence contributes to confidence score but is not required for promotion.  |
| `artifact-contract.md`       | Defines the artifact families. This policy operates on Stage 2 outputs within that framework.                                  |
| `workflow-boundaries.md`     | Defines preconditions that determine whether a run starts. This policy governns what happens with successful run outputs.      |

---

## 11. Integration with Compound-Review Skill

When the compound-review skill is updated to incorporate this policy:

1. **Phase 4 (Compound Learnings):** Check recurrence across all available authoritative runs for each learning entry. Annotate entries with `recurrence_count` and `promotion_eligibility` (eligible / not-eligible / blocked).

2. **Phase 4b (Draft Proposals):** Before emitting a skill-draft, run the conflict detection algorithm (§6). If a duplicate is found, change the draft from "new skill/rule" to "extend existing" and reference the existing target.

3. **Phase 5 (Report):** Include a promotion-readiness summary in the operator report:
    - How many findings are promotion-eligible.
    - How many have recurrence ≥2.
    - Whether any conflicts were detected.
    - Specific recommendations: extend X, create Y, or keep local.

This integration ensures that every compound-review run produces actionable promotion signals without requiring the operator to manually cross-reference history.

---

## Schema Version History

| Version | Date       | Change          |
| ------- | ---------- | --------------- |
| 1.0     | 2026-04-17 | Initial policy. |
