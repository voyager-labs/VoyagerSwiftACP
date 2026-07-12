---
description: "Deterministic adoption bridge from compound-review patch specs to committed .agents/ changes. Governs the Stage 2 to Stage 3 handoff, human review checkpoint, evidence capture, and rollback protocol."
globs: ".agents/**"
schemaVersion: 2
---

# Adoption Bridge and Rollback Protocol

## Outcome

This rule is the **Stage 3 execution protocol** for the three-stage lifecycle defined in `compound-review/references/lifecycle-contract.md`. The lifecycle contract provides stage definitions and handoff conditions; this rule provides the deterministic adoption sequence and rollback mechanics.

**Stage 1:** Work-time verification produces evidence.
**Stage 2:** compound-review synthesizes findings and emits a governance bundle with a patch spec.
**Stage 3:** This rule. Human operator adopts or rejects the patch spec.

- Follow the adoption sequence (steps 1–6) in order without skipping.
- Require a patch spec with `readiness: Needs human review` or `Ready for adoption` before proceeding.
- Require human review and diff confirmation before committing.
- Require a harness-change evaluation verdict before adoption.
- Record the commit hash in the patch spec `readiness` field and in task evidence.
- Use `git revert <commit-hash>` as the primary rollback mechanism.
- Bundle all files for one logical deliverable into one atomic commit.

## Default Actions

### 1. Validate input

Confirm the patch spec exists and is actionable:

1. Locate the patch spec at `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`.
2. Verify the `readiness` field is `Needs human review` or `Ready for adoption`.
3. Verify the `action` field is one of: `create`, `update`, `remove`.
4. Verify `target_file(s)` lists exact paths under `.agents/`.

### 2. Verify adoption prerequisites

Check that all conditions in the patch spec's `adoption_prerequisites` field are met:

1. Read the `adoption_prerequisites` list from the patch spec.
2. For each prerequisite, confirm the condition holds (e.g., prior patch adopted, finding no longer reproduces, ≥2 authoritative runs exist).
3. Confirm `99-agent/10-harness-change-evaluation.md` produced an `adopt` verdict, or that the operator explicitly accepted a documented `defer` with rationale.
4. If prerequisites are empty, proceed.

### 3. Human review checkpoint

The human operator must perform these checks:

1. **Review the patch spec**: Read rationale, source findings, proposed scope, conflict set, and non-goals.
2. **Check target files**: Confirm the target paths are correct and the action is appropriate.
3. **Check for conflicts**: Review the `conflict_set` field. If conflicts exist, verify they are acceptable.
4. **Trust classification**: Check the trust class of the Stage 2 output in the manifest. If `reference-only`, pair with additional human review. If `invalid`, do not adopt.
5. **Evaluation verdict**: Confirm the change improved behavior or document why adoption proceeds despite incomplete evidence.

### 4. Target-file diff confirmation

Before committing, the operator confirms the diff:

1. For `create` actions: review the new file content against the patch spec's proposed scope.
2. For `update` actions: run `git diff` on the target file(s) and confirm the change matches the patch spec.
3. For `remove` actions: confirm the target file(s) exist and that removal is intended.
4. Verify no run-scoped IDs or plan slugs are embedded verbatim in the target file(s) (except in evidence pointer comments).

### 5. Commit execution

1. Stage all files for this logical deliverable.
2. Commit with a conventional commit message referencing the governance change. Example format:
    ```
    refactor(governance): add {description of adopted change}
    ```
3. Record the commit hash.

### 6. Evidence capture

After the commit succeeds:

1. Update the patch spec's `readiness` field to `Adopted (commit {hash})`.
2. Record the commit hash in the task evidence file (e.g., `.sisyphus/evidence/{plan_slug}/task-{N}-{slug}.md`).
3. Verify the adopted file is in `.agents/` and the commit is in git history.

## Decision Rules

### Rollback protocol

Each adoption is one atomic commit. Rollback reverses that commit.

#### Primary rollback

```bash
git revert <adoption-commit-hash>
```

#### Post-rollback verification

1. Confirm the reverted files are restored to their pre-adoption state.
2. Check for orphan references in routing files (`10-routing/00-routing.md`) and other rule files that may reference the adopted file.
3. Remove any orphan references if found.
4. The rejected artifacts remain in `.sisyphus/` as local-only reference material — do not delete them.

#### Evidence of rollback

Record the revert commit hash in the plan-scoped task evidence file (`.sisyphus/evidence/{plan_slug}/task-{N}-*.*`). Note the reason for rollback.

### Working-tree proposals (no commit)

- Agents MAY create or edit `.agents/` files in the working tree as draft proposals.
- Working-tree changes are NOT adopted governance until committed.
- The full adoption sequence (steps 1–6) applies only when STAGING and COMMITTING changes to `.agents/`.
- Working-tree proposals require human review before staging, but do not require patch specs, evidence capture, or commit hashes.
- If the operator approves the working-tree change, proceed with the full adoption sequence at commit time.

## Stop Conditions

- Auto-COMMIT compound-review output. Working-tree drafts are fine; commits require the full protocol.
- Proceed when patch-spec validation fails or an adoption prerequisite is unmet; report the failure to the operator and stop.
- Proceed without the operator explicitly approving or rejecting the patch spec.
- Adopt a Stage 2 output classified as `invalid`.
- Treat `.sisyphus/` artifacts as durable policy. Only committed `.agents/` files are governance.
- Copy run-scoped IDs or plan slugs verbatim into `.agents/` files, except in evidence pointers of the form `Source: .sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`.
- Split a single logical deliverable across multiple commits.
- Commit a rule or skill without human review.
- Delete `.sisyphus/` artifacts after adoption (they remain as historical record).
- Bypass the patch spec's `adoption_prerequisites` field.

## Verification

- Every adopted rule or skill has a corresponding commit hash recorded in evidence.
- The patch spec's `readiness` field shows `Adopted (commit {hash})`.
- Rollback of any bundle leaves no orphaned references in other rule files.
- No `.agents/` file contains a plan slug or run ID outside of evidence pointer comments.
- The task evidence or PR body records the harness evaluation verdict and rollback path.
