# Replacement Lifecycle Contract

**Version:** 1.1
**Scope:** Defines the three-stage lifecycle that replaces the outgoing registry/verify mental model. Governs how harness changes and skill governance artifacts move from production through review to adoption or rollback.
**Source of truth for:** All skills and rules that participate in verification, review synthesis, and adoption decisions.
**Normative references:** `02-verification.md`, `07-verification-intent-parity.md`, `04-adoption-and-rollback.md`, `workflow-boundaries.md`, `artifact-contract.md`, `evidence-trust-taxonomy.md`

---

## 1. Purpose

This contract replaces the implicit "verify then adopt" mental model with an explicit three-stage lifecycle. Each stage has a defined owner, allowed inputs, expected outputs, and handoff conditions. No stage may assume responsibilities belonging to another stage.

The lifecycle applies to any change that targets `.agents/` governance artifacts (rules, skills, reference documents) and to the evidence/review artifacts that justify those changes.

---

## 2. The Three Stages

### Stage 1: Work-time Verification

**Owner:** Work-phase skills (`pr-review`, `voyager-dev`, and any skill that runs during active Work).

**When it runs:** During an active Sisyphus Work cycle, interleaved with code and artifact production.

**Allowed inputs:**

| Input                                   | Source                         |
| --------------------------------------- | ------------------------------ |
| Source code under change                | Work tasks                     |
| Test suites and test configurations     | Repository                     |
| Build artifacts and compilation results | Build system                   |
| Plan task definitions                   | `.sisyphus/plans/{slug}.md`    |
| Task-specific intent statements         | Task context from orchestrator |

**Expected outputs:**

| Output                                              | Destination              | Persistence                                  |
| --------------------------------------------------- | ------------------------ | -------------------------------------------- |
| Test results (pass/fail, coverage)                  | Console / evidence files | `.sisyphus/evidence/{plan_slug}/task-{N}-*.*`       |
| Review findings (PR comments, code quality)         | Review artifacts         | `.sisyphus/evidence/{plan_slug}/`                        |
| Verification evidence (intent parity, scope checks) | Evidence files           | `.sisyphus/evidence/{plan_slug}/task-{N}-*.*`       |
| Build status (success/failure, warnings)            | Console / evidence files | `.sisyphus/evidence/{plan_slug}/task-{N}-*.*`       |
| LSP diagnostics (errors, warnings)                  | Console                  | Transient — captured in evidence if relevant |

**Obligations:**

1. Run verification that matches the changed surface area per `02-verification.md`.
2. Verify against stated task intent, not just generic pass/fail per `07-verification-intent-parity.md`.
3. Report exact commands and pass/fail status.
4. Produce at least one evidence file per task.

**Handoff condition (Stage 1 → Stage 2):**

All of the following must hold before Work-time Verification is considered complete:

- All plan tasks are checked or explicitly closed by the operator.
- At least one evidence file exists under `.sisyphus/evidence/{plan_slug}/` matching the completed plan's tasks.
- The operator has confirmed Work is done.

**What Stage 1 must NOT do:**

- Perform compound synthesis or cross-task pattern extraction (that is Stage 2).
- Promote or adopt any artifact into `.agents/` (that is Stage 3).
- Trigger compound-review or any post-Work skill.

---

### Stage 2: Post-work Compound Review

**Owner:** `compound-review` skill exclusively.

**When it runs:** After a Sisyphus Work cycle has fully completed and the operator manually triggers the skill. Per `workflow-boundaries.md`, this skill is manual-trigger only and post-Work only.

**Allowed inputs:**

| Input                       | Source                                 | Required            |
| --------------------------- | -------------------------------------- | ------------------- |
| Completed plan file         | `.sisyphus/plans/{plan-name}.md`       | Yes (P1)            |
| Task evidence files         | `.sisyphus/evidence/{plan_slug}/task-{N}-*.*` | Yes (P2)            |
| Final review facets (f1–f4) | `.sisyphus/evidence/{plan_slug}/f{1-4}-*.md`       | Optional (OP1)      |
| Notepad files               | `.sisyphus/notepads/{plan-name}/*.md`  | Optional (OP2, OP3) |

**Expected outputs:**

| Output                                   | Destination                                            |
| ---------------------------------------- | ------------------------------------------------------ |
| Run manifest (lineage anchor)            | `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json` |
| Structured findings                      | `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json` |
| Compound learning document               | `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`  |
| Skill/harness draft proposal             | `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md` |
| Run summary                               | `.sisyphus/reviews/{plan_slug}/{run_id}/run-summary.md` |
| Failure artifact (if preconditions fail) | `.sisyphus/reviews/{plan_slug}/{run_id}/FAILURE.md`    |

**Obligations:**

1. Validate all preconditions (P1–P6, OP1–OP3) before reading artifacts per `workflow-boundaries.md` §6.
2. Classify outputs according to `evidence-trust-taxonomy.md` (authoritative, reference-only, invalid).
3. Degrade gracefully on missing optional inputs — never silently infer content.
4. Produce a governance bundle: manifest + findings + learning + draft (if threshold met) + run summary.
5. Stop after emitting outputs. Do not loop, retry, or chain into Work.

**Handoff condition (Stage 2 → Stage 3):**

All of the following must hold:

- The compound-review run completed without writing a `FAILURE.md`.
- A `manifest.json` exists at the expected path with valid lineage.
- A `skill-draft.md` exists at `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md` with `readiness` of `Needs human review` or `Ready for adoption` (or `Draft only` if no findings met the threshold).
- The operator has reviewed the output summary and decided to act on it.

**What the human operator receives:**

The governance bundle from Stage 2. The primary artifact for adoption decisions is the patch spec at `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`, which contains:

| Field                     | What the operator reviews                                                 |
| ------------------------- | ------------------------------------------------------------------------- |
| `Target File(s)`          | Exact paths under `.agents/` that will be created, updated, or removed.   |
| `Action`                  | Whether this is a create, update, or remove operation.                    |
| `Rationale`               | 1–3 paragraphs grounding the change in source findings.                   |
| `Source Findings`         | Finding IDs with dedup keys and source facets.                            |
| `Proposed Scope`          | What the patch will do, read, and verify.                                 |
| `Conflict Set`            | Files or skills that overlap with this patch.                             |
| `Non-Goals`               | What the patch explicitly does NOT do.                                    |
| `Adoption Prerequisites`  | Conditions that must hold before adoption can proceed.                    |
| `Rollback Hints`          | Steps to undo if adoption fails.                                          |
| `Readiness`               | Current status: `Draft only`, `Needs human review`, `Ready for adoption`. |
| `Source-Artifact Linkage` | Table linking findings to severity and issue descriptions.                |

**What the human operator must do (adoption sequence):**

The full adoption sequence is defined in `04-adoption-and-rollback.md`. Summary:

1. **Validate input**: Confirm the patch spec exists with actionable `readiness`.
2. **Verify adoption prerequisites**: Confirm all conditions in `adoption_prerequisites` are met.
3. **Human review checkpoint**: Review rationale, scope, conflicts, and trust classification.
4. **Target-file diff confirmation**: Confirm the diff matches the patch spec intent.
5. **Commit execution**: Atomic commit with conventional commit message.
6. **Evidence capture**: Record commit hash in patch spec readiness and task evidence.

**What happens after adoption:**

- The patch spec's `readiness` field is updated to `Adopted (commit {hash})`.
- The commit hash is recorded in task evidence (`.sisyphus/evidence/{plan_slug}/`).
- The adopted files are now governed by normal rule maintenance.
- The `.sisyphus/` artifacts remain as local-only historical record and are NOT deleted.

**What Stage 2 must NOT do:**

- Run tests, build code, or perform any verification (that is Stage 1).
- Modify any file in `.agents/`, `apps/`, or any directory outside approved write paths.
- Commit changes, create PRs, or mutate git state.
- Auto-trigger adoption or rollback (that is Stage 3, human-initiated).
- Re-plan, re-open completed tasks, or trigger new Work cycles.

---

### Stage 3: Human-reviewed Adoption or Rollback

**Owner:** Human operator, with agent assistance for mechanical steps.

**When it runs:** After the operator has reviewed Stage 2 outputs and decided to promote, modify, or reject the proposed changes.

**Allowed inputs:**

| Input                                      | Source                                                 |
| ------------------------------------------ | ------------------------------------------------------ |
| Skill/harness draft proposals from Stage 2 | `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md` |
| Compound learning documents from Stage 2   | `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`  |
| Structured findings from Stage 2           | `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json` |
| Run manifest (lineage anchor)              | `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json` |
| Operator judgment                          | Human decision                                         |

**Expected outputs:**

| Output (Adoption path)           | Destination                           |
| -------------------------------- | ------------------------------------- |
| New or modified rule/skill files | `.agents/rules/` or `.agents/skills/` |
| Commit with governance bundle    | Git history                           |
| Commit hash recorded in evidence | `.sisyphus/evidence/{plan_slug}/`                 |

| Output (Rollback path)              | Destination                                       |
| ----------------------------------- | ------------------------------------------------- |
| `git revert` of the adoption commit | Git history                                       |
| Confirmation of orphan cleanup      | Evidence file                                     |
| No new `.agents/` changes           | N/A — artifacts stay in `.sisyphus/` (local-only) |

**Obligations:**

1. The operator reviews Stage 2 outputs before any adoption action. No agent may auto-adopt.
2. Bundle a rule file and all its references into one atomic commit per `04-adoption-and-rollback.md`.
3. Record the commit hash in the task evidence file after adoption.
4. Use concrete `git revert` commands for rollback, not manual file deletion.
5. After reverting, confirm no orphan references remain in routing or other rule files.

**Handoff condition (Stage 3 → lifecycle end):**

- **Adoption path:** Changes are committed to `.agents/`, commit hash recorded in evidence, mirror synced (if applicable). Lifecycle ends; changes are now governed by normal rule maintenance.
- **Rollback path:** Revert commit applied, orphan references cleaned. Lifecycle ends; the rejected artifacts remain in `.sisyphus/` as local-only reference material.

**What Stage 3 must NOT do:**

- Skip human review of Stage 2 outputs.
- Auto-adopt without operator confirmation.
- Split a single logical deliverable across multiple commits.
- Delete `.sisyphus/` artifacts (they remain as historical record).

---

## 3. Stage Boundaries

These boundaries are non-negotiable. Crossing them violates the lifecycle contract.

| Boundary                          | Rule                                                                                                                                                                                                  |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No backward flow**              | A later stage must not invoke an earlier stage. Stage 3 cannot re-run Stage 1 tests. Stage 2 cannot trigger Stage 1 verification.                                                                     |
| **No cross-stage responsibility** | Each stage owns its obligations exclusively. Stage 2 does not verify code. Stage 1 does not synthesize compound learnings. Stage 3 does not review artifacts.                                         |
| **No bypass**                     | No stage may be skipped. An adoption cannot proceed without Stage 2 output. Stage 2 cannot run without Stage 1 evidence.                                                                              |
| **No stage auto-advancement**     | The transition from one stage to the next requires explicit action: Stage 1 → Stage 2 requires operator to trigger compound-review. Stage 2 → Stage 3 requires operator to review outputs and decide. |

---

## 4. Failure Handling Per Stage

### Stage 1 failures

- Test failures, build errors, or verification gaps are resolved within Stage 1.
- The agent fixes issues and re-verifies until the handoff condition is met.
- If the agent cannot resolve an issue, it reports to the operator and waits.

### Stage 2 failures

- Per `artifact-contract.md` §Failure Rules:
    - **Report-and-stop:** Write `FAILURE.md` describing the condition, then halt. Used for missing required inputs, stale lineage, ambiguous targets, conflicting runs.
    - **Degrade-gracefully:** Proceed with reduced confidence. Set `confidence_reduced: true` in manifest. Used for missing optional inputs.
- No silent inference. Every degradation is explicitly noted.
- The operator must resolve the failure condition before a new Stage 2 run can succeed.

### Stage 3 failures

- If the operator rejects the proposed changes, no adoption occurs. Artifacts stay in `.sisyphus/` as local-only reference.
- If an adopted change proves incorrect, the operator reverts using `git revert <commit-hash>` per `04-adoption-and-rollback.md`.

---

## 5. Trust Classification Integration

Stage 2 outputs are classified using `evidence-trust-taxonomy.md`. The trust class of Stage 2 outputs determines what actions Stage 3 may take:

| Trust class      | Stage 3 action                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------- |
| `authoritative`  | Operator may proceed with adoption based on these findings.                                             |
| `reference-only` | Operator should NOT base adoption solely on these outputs. Pair with human review or a new Stage 2 run. |
| `invalid`        | Operator must NOT adopt. Fix inputs and re-run Stage 2 first.                                           |

---

## 6. Terminology

This section defines terms that the lifecycle uses and prohibits alternatives that would confuse the stage boundaries.

### Preferred terms

| Term                                 | Definition                                                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| **Work-time verification**           | Stage 1. Verification that runs during active Work: tests, reviews, intent-parity checks.                    |
| **Post-work compound review**        | Stage 2. Read-only synthesis of completed Work artifacts. Produces findings, learnings, and draft proposals. |
| **Human-reviewed adoption/rollback** | Stage 3. Operator-driven promotion or rejection of Stage 2 proposals.                                        |
| **Governance bundle**                | The set of artifacts produced by Stage 2 (manifest, findings, learning, draft) that feeds into Stage 3.      |
| **Handoff condition**                | The explicit checklist that must be satisfied before advancing to the next stage.                            |

### Prohibited descriptions of compound-review

The following terms must NOT be used to describe compound-review (Stage 2), because they imply capabilities or responsibilities that belong to other stages:

| Prohibited term | Why it is wrong                                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `pre-merge`     | compound-review is not a merge gate. It runs post-Work, not pre-merge. Adoption is a separate human decision in Stage 3.                         |
| `CI gate`       | compound-review is not a CI step. It is a manually triggered, local-repo-only skill. It does not block, approve, or gate any automated pipeline. |
| `auto-apply`    | compound-review never auto-applies changes. Its draft proposals are inputs for `skill-creator` or operator action, not auto-committed artifacts. |

---

## 7. Relationship to Existing Rules

This lifecycle contract does not replace or modify existing governance rules. It provides the overarching framework within which they operate:

| Existing rule                      | Lifecycle relationship                                                                                                                            |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `02-verification.md`               | Defines the verification matrix that Stage 1 follows. Unchanged.                                                                                  |
| `07-verification-intent-parity.md` | Defines intent-based verification that Stage 1 follows. Unchanged.                                                                                |
| `04-adoption-and-rollback.md`      | Defines the deterministic adoption bridge (6-step sequence) and rollback protocol that Stage 3 follows. This contract provides lifecycle context. |
| `workflow-boundaries.md`           | Defines operating boundaries for compound-review (Stage 2). Unchanged.                                                                            |
| `artifact-contract.md`             | Defines artifact families and failure rules for Stage 2. Unchanged.                                                                               |
| `evidence-trust-taxonomy.md`       | Defines trust classification for Stage 2 outputs. Unchanged.                                                                                      |

---

## 8. Visual Flow

```
┌─────────────────────────┐
│  Stage 1: Work-time      │
│  Verification            │
│                           │
│  Owner: work-phase skills │
│  (pr-review, voyager-dev, │
│   etc.)                   │
│                           │
│  Produces: evidence,     │
│  test results, review    │
│  findings                │
└───────────┬───────────────┘
            │
            │ Handoff: all tasks complete,
            │ evidence exists, operator confirms
            ▼
┌─────────────────────────┐
│  Stage 2: Post-work      │
│  Compound Review         │
│                           │
│  Owner: compound-review   │
│  (manual trigger, read-  │
│   only, local-repo only) │
│                           │
│  Produces: manifest,     │
│  findings, learning,     │
│  patch spec              │
└───────────┬───────────────┘
            │
            │ Handoff: governance bundle
            │ with patch spec (readiness ≥
            │ Needs human review)
            ▼
┌─────────────────────────┐
│  Stage 3: Adoption       │
│  Bridge                  │
│  (04-adoption-and-       │
│   rollback.md)           │
│                           │
│  1. Validate input       │
│  2. Verify prerequisites │
│  3. Human review         │
│  4. Diff confirmation    │
│  5. Commit execution     │
│  6. Evidence capture     │
│                           │
│  Rollback:               │
│  git revert <hash>       │
└─────────────────────────┘
```

---

## Schema Version History

| Version | Date       | Change                                                                                                      |
| ------- | ---------- | ----------------------------------------------------------------------------------------------------------- |
| 1.1     | 2026-04-17 | Enhanced Stage 2 → Stage 3 handoff with adoption bridge details, operator receipt table, and post-adoption. |
| 1.0     | 2026-04-17 | Initial.                                                                                                    |
