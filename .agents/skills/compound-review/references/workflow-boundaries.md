# Workflow Boundaries and Invocation Semantics

**Version:** 1.0
**Scope:** Defines the operating rules, trigger constraints, read/write boundaries, and hard prohibitions for the compound-review skill.
**Source of truth for:** Task 2 operating rules. Downstream tasks (4, 5, 6) must conform to these boundaries.

---

## 1. Trigger Mode

The skill is **manual-trigger only**.

It activates only when the operator explicitly invokes it through the skill system (e.g., `compound-review` or an equivalent explicit call). The skill must not:

- Activate on file-save events, git hooks, CI signals, or timer-based schedules.
- Self-invoke from within another skill's completion handler unless the operator explicitly requests it.
- Chain automatically from `test-runner`, `pr-review`, `verify-implementation`, or any other skill.

**Rationale:** The review → compound workflow reads completed artifacts and synthesizes findings. It must run only after the operator has inspected the completed work and decided a compound review is warranted. Auto-triggering would bypass human judgment about whether the artifact set is ready.

---

## 2. Temporal Boundary

The skill is **post-Work only**.

It runs only after a Sisyphus Work cycle has completed for the target plan. Completion means:

- All plan TODOs are checked or explicitly closed by the operator.
- At least one evidence file exists under `.sisyphus/evidence/` matching the target plan's tasks.
- The operator has confirmed Work is done.

The skill must not:

- Run concurrently with an active Work cycle on the same plan.
- Run on a plan that is still in progress (unchecked TODOs, missing evidence).
- Trigger new Work, re-planning, or continuation of an incomplete plan.

**Rationale:** The compound review reads and synthesizes. If Work is still in progress, inputs are unstable. Findings would be based on partial state, producing unreliable synthesis.

---

## 3. Scope Boundary

The skill is **local-repo only**.

All reads and writes happen within the current repository checkout. The skill must not:

- Fetch artifacts from remote repositories, APIs, databases, or external services.
- Push artifacts to remote storage, CI systems, or issue trackers.
- Depend on network-available state that could diverge from the local checkout.

**Rationale:** v1 stays simple. The `.sisyphus` directory is the single source of truth. Cross-repo or networked artifact resolution adds complexity that provides no value for the initial workflow.

---

## 4. Read/Write Boundary

The skill is **read-mostly** over `.sisyphus` and **write-only** to approved output paths.

### Read paths (no mutation)

| Path                                          | Purpose                                                                       |
| --------------------------------------------- | ----------------------------------------------------------------------------- |
| `.sisyphus/plans/{plan-name}.md`              | Source plan. Read for compliance checking and scope fidelity. Never modified. |
| `.sisyphus/evidence/task-{N}-{slug}.*`        | Per-task evidence. Read for finding extraction. Never modified.               |
| `.sisyphus/evidence/f1-plan-compliance.md`    | Final review facet (stable filename).                                         |
| `.sisyphus/evidence/f2-code-quality.md`       | Final review facet (stable filename).                                         |
| `.sisyphus/evidence/f3-manual-qa.md`          | Final review facet (stable filename).                                         |
| `.sisyphus/evidence/f4-scope-fidelity.md`     | Final review facet (stable filename).                                         |
| `.sisyphus/notepads/{plan-name}/learnings.md` | Notepad family member.                                                        |
| `.sisyphus/notepads/{plan-name}/decisions.md` | Notepad family member.                                                        |
| `.sisyphus/notepads/{plan-name}/issues.md`    | Notepad family member.                                                        |
| `.sisyphus/notepads/{plan-name}/problems.md`  | Notepad family member.                                                        |

The skill must not modify, rename, move, or delete any file it reads. If a read path has changed since the run started (stale detection), the skill reports and stops per the artifact contract failure rules.

### Approved write paths

| Path                                                   | Purpose                       | Condition                                      |
| ------------------------------------------------------ | ----------------------------- | ---------------------------------------------- |
| `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json` | Run manifest.                 | Created once per run.                          |
| `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json` | Structured findings.          | Created once per run.                          |
| `.sisyphus/reviews/{plan_slug}/{run_id}/FAILURE.md`    | Failure artifact.             | Created only on report-and-stop conditions.    |
| `.sisyphus/compound/{plan_slug}/{run_id}/learning.md`  | Compound learning document.   | Created once per run (not created on failure). |
| `.sisyphus/drafts/{plan_slug}/{run_id}/skill-draft.md` | Skill/harness draft proposal. | Created once per run (not created on failure). |

The skill must not write anywhere else. Specifically, it must not:

- Write to `.sisyphus/plans/`, `.sisyphus/evidence/`, or `.sisyphus/notepads/`.
- Modify any product source file under `apps/`, `docs/`, or any other source directory.
- Modify any rule or skill file under `.agents/`.
- Create or modify files outside the `.sisyphus` directory.

---

## 5. Hard Prohibitions

These actions are **unconditionally forbidden** for the compound-review skill:

| Prohibition                                | Reason                                                                                                                                                                                              |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Re-planning**                            | The skill reads a completed plan. Re-opening plan scope would violate the post-Work boundary. If the plan needs changes, the operator starts a new planning cycle.                                  |
| **Code mutation outside approved outputs** | The skill is read-mostly. Product code, rules, and other skills are outside its write scope.                                                                                                        |
| **Commits**                                | The skill produces review artifacts, not git history. The operator decides when and what to commit.                                                                                                 |
| **Pull requests**                          | PR creation is outside scope. `pr-execution` handles that.                                                                                                                                          |
| **Automatic Work loops**                   | The skill must not trigger `/start-work`, `ralph`, `autopilot`, or any execution engine. It ends after writing its outputs.                                                                         |
| **Inference on missing artifacts**         | If a required artifact is missing, the skill reports and stops. It must not guess what the artifact would have contained. For optional artifacts, it degrades gracefully without inferring content. |
| **Silent degradation**                     | Every degradation is explicitly noted in the manifest (`facets_missing`, `missing_sources`, `confidence_reduced`). No silent inference.                                                             |
| **Branch mutation**                        | The skill must not create, switch, or delete git branches.                                                                                                                                          |
| **Environment mutation**                   | The skill must not modify `.env` files, Xcode schemes, CI configs, or any environment state.                                                                                                        |

---

## 6. Preconditions for a Valid Run

Before the skill can execute its review + compound synthesis, all of the following must hold. If any precondition fails, the skill reports the failure and stops.

| ID  | Precondition                                                                             | Check Method                                                                    | Failure Action                        |
| --- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------- |
| P1  | A completed plan exists at `.sisyphus/plans/{plan-name}.md`.                             | File exists and is readable.                                                    | Report-and-stop.                      |
| P2  | At least one evidence file matching `task-{N}-{slug}.*` exists in `.sisyphus/evidence/`. | Directory listing for files matching the pattern.                               | Report-and-stop.                      |
| P3  | The plan slug is unambiguous (see `target-selection.md`).                                | Exactly one candidate plan matches, or operator has specified the target.       | Report-and-stop with ambiguity error. |
| P4  | No conflicting run exists for the same plan_slug and run_id.                             | Check if `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json` already exists. | Report-and-stop.                      |
| P5  | The target plan has not been modified after Work completion evidence timestamps.         | Compare plan file mtime against the latest evidence file mtime for the plan.    | Report-and-stop (stale lineage).      |
| P6  | The run_id can be determined or generated.                                               | Current timestamp in `YYYY-MM-DD-HHMMSS` format.                                | Generate automatically.               |

### Optional precondition checks (degrade, not stop)

| ID  | Precondition                                                                | Check Method                                               | On Failure                                 |
| --- | --------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------ |
| OP1 | Final review facets (f1-f4) are present.                                    | Check for exact stable filenames in `.sisyphus/evidence/`. | Degrade-gracefully. Note `facets_missing`. |
| OP2 | Notepad directory exists for the plan.                                      | Directory listing at `.sisyphus/notepads/{plan_slug}/`.    | Continue with warning in manifest.         |
| OP3 | At least one of `learnings.md` or `decisions.md` exists in the notepad dir. | File existence check.                                      | Degrade-gracefully. Note in manifest.      |

---

## 7. Run Lifecycle

A single invocation of the skill follows this lifecycle. The skill completes exactly one cycle per invocation and then exits.

```
1. Validate preconditions (P1-P6, OP1-OP3)
   ├── Any P-failure → write FAILURE.md, stop
   └── All P-pass → continue

2. Read all available input artifacts
   ├── Plan file
   ├── Evidence files (sorted alphabetically)
   ├── Present facets (f1-f4 by stable filename)
   └── Present notepad files (full family)

3. Synthesize findings
   ├── Extract findings from facets and evidence
   ├── Deduplicate by dedupe_key
   └── Assign severity, owner, action_class

4. Write run manifest
   └── manifest.json with full input/output enumeration

5. Write structured findings
   └── findings.json

6. Write compound learning document
   └── learning.md

7. Write skill/harness draft (if applicable)
   └── skill-draft.md

8. Report completion to operator
   └── Summary of findings count, missing inputs, and output paths
```

The skill must not loop, retry, or chain into additional work after step 8. It exits.

---

## 8. Operator Responsibilities

The skill assumes the operator (human) handles:

- Deciding when to invoke the review (manual trigger).
- Choosing the target plan when multiple candidates exist (see `target-selection.md`).
- Reviewing the skill's output and deciding next steps.
- Committing outputs to version control if desired.
- Starting new Work cycles, re-planning, or other follow-up actions.

The skill does not make these decisions. It reports findings and exits.
