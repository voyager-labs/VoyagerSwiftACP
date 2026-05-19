# Target-Case Selection Rules

**Version:** 1.0
**Scope:** Defines how the compound-review skill selects the target plan/case when invoked, including deterministic precedence rules and ambiguity resolution.
**Source of truth for:** Task 2 target selection. Downstream tasks (4, 5, 6) must use these rules when resolving the target case.

---

## 1. What the Target Case Is

The "target case" is the completed plan (and its associated artifacts) that the compound-review skill will review and synthesize. A case is identified by its **plan slug**: the filename of the plan under `.sisyphus/plans/` minus the `.md` extension.

For example, `.sisyphus/plans/voy-208-grid-drop-interaction-stabilization.md` has plan slug `voy-208-grid-drop-interaction-stabilization`.

---

## 2. Selection Modes

The skill supports two selection modes. Explicit operator specification always takes priority over automatic detection.

### Mode A: Explicit Specification

The operator provides the plan slug directly when invoking the skill.

**Examples:**

- `compound-review --plan voy-208-grid-drop-interaction-stabilization`
- `compound-review voy-208-grid-drop-interaction-stabilization`

When the operator specifies a plan slug:

1. Look up `.sisyphus/plans/{slug}.md`. If it does not exist, report-and-stop with a clear error: the specified plan was not found.
2. Proceed with that plan as the target case.
3. Do not scan for other candidate plans.

**Rationale:** The operator knows what they want reviewed. No guessing needed.

### Mode B: Automatic Detection

When no plan slug is provided, the skill attempts automatic detection using the deterministic rules below.

---

## 3. Automatic Detection: Deterministic Precedence Rules

When the operator does not specify a target, the skill follows these steps in order. It stops at the first step that resolves to exactly one candidate.

### Step 1: Active Worktree Branch Match

1. Read the current git branch name.
2. Extract the Linear issue key or worktree identifier from the branch name. Common patterns:
    - `feature/voy-123`, `fix/voy-456`, `refactor/voy-142` → extract `voy-{N}`
    - `hotfix/voy-789` → extract `voy-{N}`
3. Find plan files in `.sisyphus/plans/` whose filename starts with the extracted issue key.
4. If exactly one match → use it. If zero or multiple → proceed to Step 2.

**Example:** Branch `refactor/voy-142` extracts key `voy-142`. If `.sisyphus/plans/voy-142-compound-review-harness.md` exists, it matches.

### Step 2: Single Completed Plan

1. List all `.md` files in `.sisyphus/plans/`.
2. For each, check completion: does it have evidence files in `.sisyphus/evidence/{plan_slug}/` with matching task patterns?
3. If exactly one completed plan exists → use it.
4. If zero → report-and-stop: no completed plans found.
5. If two or more → proceed to Step 3.

### Step 3: Most Recently Modified Completed Plan

1. From the set of completed plans found in Step 2, sort by file modification time (most recent first).
2. Select the most recently modified plan.
3. **Before proceeding**, report the selection to the operator: "Multiple completed plans found. Selected `{slug}` as the most recently modified. To target a different plan, re-run with `--plan {slug}`."
4. Proceed with the selected plan.

**Rationale for most-recent precedence:** When multiple plans exist without operator guidance, the most recently modified plan is the most likely current target. But the skill still reports the selection so the operator can override on a subsequent run.

### Step 4: Ambiguity Unresolved

If none of the above steps resolve to a single candidate:

1. List all candidate plan slugs with their modification times and evidence file counts.
2. Report-and-stop: "Unable to determine target case. Multiple candidates found: [list]. Please re-run with `--plan {slug}`."

**No guessing.** The skill does not pick a plan at random, use heuristics beyond modification time, or silently skip a candidate.

---

## 4. Run ID Selection Within a Case

Once the target plan slug is determined, the skill must determine or generate a `run_id`.

### New Run (default)

If no existing run directory exists for this plan_slug, generate a new `run_id`:

- Format: `YYYY-MM-DD-HHMMSS` (timestamp at invocation time).
- This is the standard behavior for each invocation.

### Existing Run Detection

If `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json` already exists for a given run_id:

- The skill must not overwrite or append to an existing run.
- Report-and-stop: "Run `{run_id}` already exists for plan `{plan_slug}`. To re-review, use a new invocation (which generates a new run_id)."

### Multiple Prior Runs

If prior runs exist for the same plan_slug (different run_ids), the new run proceeds normally with a fresh run_id. Prior runs are not modified.

---

## 5. Evidence Association Rules

The skill associates evidence files with the target plan using these rules:

### Direct Pattern Match

Evidence files matching `task-{N}-*.*` are associated with the plan if:

1. The evidence file's slug portion contains or matches a substring of the plan slug, OR
2. The plan file itself references the evidence file name in its task descriptions.

### Ambiguous Evidence

If evidence files could plausibly belong to multiple plans:

1. Associate evidence only with plans that reference the evidence file name explicitly in their task list.
2. If no plan explicitly references the evidence file, associate it with the target plan only if the plan slug appears as a substring of the evidence file slug.
3. If still ambiguous, exclude the evidence file from the current run and note the exclusion in the manifest.

### Final Review Facets

Facet files (`f1-plan-compliance.md`, `f2-code-quality.md`, `f3-manual-qa.md`, `f4-scope-fidelity.md`) are slug-independent and are associated with whichever plan is the target case. They are detected by exact stable filename, not by slug interpolation.

---

## 6. Notepad Association Rules

Notepad directories are associated with the target plan:

1. Exact match: `.sisyphus/notepads/{plan_slug}/` matches the plan slug directly.
2. If no exact match exists, the skill proceeds without notepad consumption (continue with warning in manifest).
3. The skill does not search for partial or fuzzy matches on notepad directory names.

---

## 7. Prior Run Association Rules

When the target plan has been previously reviewed, prior runs provide cross-run context for dedup and trend detection.

### Detecting Prior Runs

1. List directories under `.sisyphus/reviews/{plan_slug}/`.
2. Any directory containing a `manifest.json` is a prior run.
3. Exclude the current `run_id` (being generated) from the prior set.

### Prior Run Consumption

Prior runs are optional inputs. If they exist:

1. Read the prior `manifest.json` for lineage and confidence metadata.
2. Read the prior `findings.json` for `dedupe_key` comparison with current findings.
3. Read the prior `learning.md` (in `.sisyphus/reviews/{plan_slug}/{prior_run_id}/`) for overlap detection.
4. The most recent prior run that is `authoritative` (per `evidence-trust-taxonomy.md`) is the primary cross-run baseline.

If no prior runs exist, the skill proceeds without cross-run context. This is normal for first-time reviews and carries no degradation penalty.

---

## 8. Summary: Decision Flow

```
Operator invokes compound-review
├── Plan slug provided? → Mode A (explicit)
│   ├── Plan file exists? → Use it
│   └── Plan file missing? → Report-and-stop
└── No plan slug? → Mode B (automatic)
    ├── Step 1: Branch match → single result? → Use it
    ├── Step 2: Single completed plan? → Use it
    ├── Step 3: Most recent completed plan → Report selection, use it
    └── Step 4: Cannot resolve → Report-and-stop, list candidates
```

At every step, the skill either resolves deterministically or reports ambiguity to the operator. There is no "best effort" selection.
