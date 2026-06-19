---
name: compound-review
description: Post-Work review and compound learning synthesis for completed Sisyphus plans. Reads completed .sisyphus artifacts, extracts structured findings, produces reusable learning documents, and drafts skill/harness improvement proposals. Manual trigger only, local-repo only, read-mostly. Use this skill after a Work cycle completes, when you want to review evidence, compound learnings, or propose harness improvements. Do NOT use during active Work, for PR creation, code changes, or test execution.
---

# Compound Review — Review → Compound Synthesis

## Purpose

Read completed `.sisyphus` artifacts from a finished Work cycle, synthesize structured findings, compound reusable learnings, and draft skill/harness improvement proposals. The skill is a **read-only observer** that emits structured analysis artifacts. It does not plan, code, commit, create PRs, or trigger Work loops.

## What This Skill Is Not

This skill does not replace Work-phase verification skills (`pr-review`, `voyager-dev`, etc.). Those run during Work. This runs after Work, reading what they (and the operator) produced. It also does not replace `skill-creator`. Draft proposals from this skill are inputs for `skill-creator`, not auto-applied.

---

## Operating Boundaries

These boundaries are non-negotiable. They are defined in full at `references/workflow-boundaries.md`. The summary below is the quick reference; the reference doc is the source of truth.

| Boundary              | Rule                                                                                                                                                     |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| **Trigger**           | Manual only. No auto-trigger from hooks, CI, or skills.                                                                                                  |
| **Temporal**          | Post-Work only. Plan must be completed with evidence.                                                                                                    |
| **Scope**             | Local-repo only. No network, no remote artifacts.                                                                                                        |
| **Read**              | `.sisyphus/plans/`, `.sisyphus/evidence/{plan_slug}/`, `.sisyphus/notepads/` — never modify.                                                             |
| **Write**             | `.sisyphus/reviews/` — nowhere else. Learning, draft, run summary, findings, manifest, and failures all live under the review run root.                  |     |
| **Hard prohibitions** | No re-planning, code mutation, commits, PRs, auto-Work loops, inference on missing artifacts, silent degradation, branch mutation, environment mutation. |

---

## Phases

The skill runs through five sequential phases. Each phase has explicit entry conditions and stopping rules. If any phase fails its entry check, the skill writes a `FAILURE.md` artifact and stops.

### Phase 1: Validate Inputs

**Goal:** Confirm a valid, completable run is possible before reading any artifacts.

Read `references/target-selection.md` for the full target resolution algorithm. The short version:

1. **Resolve the target plan.** If the operator specified a plan slug, use it. Otherwise, use automatic detection: git branch match → single completed plan → most recently modified completed plan → report ambiguity and stop.
2. **Check required preconditions (P1–P6).** These are defined in `references/workflow-boundaries.md` §6. Quick summary:
    - P1: Plan file exists at `.sisyphus/plans/{slug}.md`
    - P2: At least one evidence file matching `.sisyphus/evidence/{plan_slug}/task-{N}-*.*` exists
    - P3: Plan slug is unambiguous
    - P4: No conflicting run already exists for this plan_slug + run_id
    - P5: Plan file not modified after evidence timestamps
    - P6: Run ID can be generated (`YYYY-MM-DD-HHMMSS` from current time)
3. **Check optional preconditions (OP1–OP3).** Missing optional inputs degrade gracefully rather than stopping:
    - OP1: f1–f4 final review facets present
    - OP2: Notepad directory exists
    - OP3: At least one of `learnings.md` or `decisions.md` in notepad dir
4. **Generate `run_id`** as `YYYY-MM-DD-HHMMSS`.

**Stop conditions:**

- Any P-failure → write `FAILURE.md` at `.sisyphus/reviews/{plan_slug}/{run_id}/FAILURE.md`, then stop.
- Ambiguous target → report-and-stop with candidate list.

### Phase 2: Read and Inventory Artifacts

**Goal:** Read all available input artifacts and build the full input enumeration for the manifest.

1. **Read the plan file** at `.sisyphus/plans/{slug}.md`.
2. **Collect evidence files.** List all files matching `task-{N}-*.*` in `.sisyphus/evidence/{plan_slug}/`. Sort alphabetically. These are associated with the target plan per `references/target-selection.md` §5.
3. **Detect final review facets.** Check for exact stable filenames in `.sisyphus/evidence/{plan_slug}/`:
    - `f1-plan-compliance.md`
    - `f2-code-quality.md`
    - `f3-manual-qa.md`
    - `f4-scope-fidelity.md`

    Facets are slug-independent. Detect by exact filename match, not by slug interpolation. Each facet file MUST follow the format defined in `references/artifact-contract.md` §Facet File Requirements (Reviewer, Session, Verdict, Findings, Evidence fields).

4. **Collect notepad files.** Look in `.sisyphus/notepads/{plan_slug}/` for `learnings.md`, `decisions.md`, `issues.md`, `problems.md`.
5. **Discover and collect knowledge entries (optional).** Knowledge is a cross-session input family managed by `sisyphus-wiki`, not plan-scoped:
    - Read `.sisyphus/knowledge/index.json` to discover available entries (each entry has `id`, `title`, `type`, `status`, `path`, `tags[]`).
    - Associate entries by **tag matching**: match entry tags against `plan_slug` substrings, plan context keywords, and notepad topics. See `references/target-selection.md` §6 for full association rules.
    - Read matched knowledge entry files (`.sisyphus/knowledge/entries/*.md`).
    - Optionally read `.sisyphus/knowledge/graph.jsonl` for cross-entry edges relevant to matched entries.
    - If `index.json` is missing or empty, or no entries match, skip knowledge consumption entirely (degrade-gracefully).

**Stop conditions:**

- Stale detection: if any input file was modified after `run_at` → write `FAILURE.md` and stop.

### Phase 3: Synthesize Findings

**Goal:** Extract, normalize, and deduplicate structured findings from all consumed artifacts.

1. **Extract findings** from each available source:
    - f1 (plan compliance) → scope, plan fidelity findings
    - f2 (code quality) → code-quality, design findings
    - f3 (manual QA) → regression-risk, test-coverage findings
    - f4 (scope fidelity) → scope, guardrail findings
    - Task evidence files → supplemental findings
    - Notepad files → contextual enrichment (decisions, known issues)
2. **Normalize each finding** using the field set defined in `references/findings-schema.md`. Every finding needs: `id`, `severity`, `owner`, `action_class`, `category`, `title`, `description`, `source_artifacts`, `dedupe_key`, `verdict`.
3. **Deduplicate** by `dedupe_key`:
    - Same dedupe_key from different sources → keep the one with more `source_artifacts`
    - If equal source count → keep higher severity
    - If still equal → keep lower FIND-ID
    - Add `collapsed_from` array to surviving finding listing merged IDs
4. **Assign `facets_consumed` and `facets_missing`** in the findings output.

**Reference:** `references/findings-schema.md` is the authoritative schema. Read it for all field definitions, enumerated values, and dedup rules. Do not invent fields or values not in that schema.

### Phase 4: Compound Learnings and Draft Proposals

**Goal:** Derive reusable knowledge and improvement proposals from synthesized findings.

#### 4a. Compound Learning Document

Write to `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`.

For each cluster of related findings (grouped by `category`), produce a learning entry with:

- **Category** (H2 section header)
- **Title** (H3)
- **Type:** `bug-resolution` or `harness-guidance`
- **Tags:** array of lowercase hyphenated tags
- **Applies when:** concrete preconditions
- **Guidance:** do/don't rules
- **Source:** lineage to findings and facets

The `type` distinction matters:

- `bug-resolution` encodes correct fix patterns for bugs that were found and resolved
- `harness-guidance` encodes test/verification patterns that future agents should follow

**Reference:** `references/learning-schema.md` is the authoritative schema for structure, fields, and examples.

#### 4b. Skill / Harness Draft Proposal

Write to `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`.

A draft is emitted when at least one finding meets the threshold (non-APPROVE verdict, or APPROVE with `test-coverage`/`design` action class, AND severity medium or higher). If no findings meet the threshold, write a minimal draft noting "No findings met the draft threshold."

Each draft contains: rationale, source findings, proposed scope, target file, non-goals, readiness status, and the Source-Artifact Linkage table.

**Reference:** `references/skill-draft-schema.md` is the authoritative schema for structure, threshold rules, and examples.

### Phase 5: Emit Outputs and Report

**Goal:** Write all output artifacts and report completion to the operator.

Write these files in order:

1. **Manifest** → `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json`
2. **Findings** → `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json`
3. **Learning** → `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`
4. **Draft** → `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`
5. **Run summary** → `.sisyphus/reviews/{plan_slug}/{run_id}/run-summary.md`

All schemas are in `references/`:

- `references/manifest-schema.md` for manifest.json
- `references/findings-schema.md` for findings.json
- `references/learning-schema.md` for learning.md
- `references/skill-draft-schema.md` for skill-draft.md
- `references/artifact-contract.md` for run-summary.md

After writing, report to the operator:

- Total findings count, grouped by severity
- Missing inputs (facets, notepads) that triggered degraded confidence
- Exact output paths for all five artifacts
- Whether any draft proposals met the threshold

**Then stop.** The skill exits after this report. It does not loop, retry, or chain into Work.

---

## Reference Index

These files are the source of truth for their respective domains. The SKILL.md body summarizes and points to them; it does not duplicate their rules inline.

| Reference                           | Purpose                                                                                     |
| ----------------------------------- | ------------------------------------------------------------------------------------------- |
| `references/artifact-contract.md`   | Input/output families, lineage, failure rules, path structure                               |
| `references/workflow-boundaries.md` | Trigger mode, temporal/scope boundaries, read/write rules, hard prohibitions, preconditions |
| `references/target-selection.md`    | Deterministic target resolution, run ID handling, evidence/notepad association              |
| `references/manifest-schema.md`     | manifest.json field definitions and examples                                                |
| `references/findings-schema.md`     | findings.json field definitions, enumerated values, dedup rules                             |
| `references/learning-schema.md`     | learning.md structure, type distinction, entry fields                                       |
| `references/skill-draft-schema.md`  | skill-draft.md structure, threshold, linkage table                                          |

When in doubt about a rule, field name, or value, the reference doc wins over any summary in this file.

---

## Failure Behavior Summary

Full failure table is in `references/artifact-contract.md` §Failure Rules. The two failure actions are:

- **Report-and-stop:** Write `FAILURE.md` describing the condition, then halt. Used for missing required inputs, stale lineage, ambiguous targets, conflicting runs.
- **Degrade-gracefully:** Proceed with reduced confidence. Set `confidence_reduced: true` in manifest, add `facets_missing` and `missing_sources`. Used for missing optional inputs (facets, notepads).

No silent inference. Every degradation is explicitly noted.

---

## Relationship to Other Skills

| Skill                          | Relationship                                                                                                            |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `pr-review`                    | Runs during Work. Produces review comments. Compound-review reads those outputs post-Work.                              |
| `voyager-dev`                  | Runs during Work for Voyager/macOS implementation and test verification. Compound-review reads its evidence post-Work.  |
| Work-phase verification skills | Run during Work (`pr-review`, `voyager-dev`, etc.). Produce verification evidence that compound-review reads post-Work. |
| `skill-creator`                | Consumes compound-review draft proposals. Compound-review drafts are input for skill-creator, not auto-applied.         |

---

## When to Use This Skill

Trigger this skill when:

- A Sisyphus Work cycle has completed and you want a structured review synthesis
- You want to compound learnings from a completed plan's evidence and review facets
- You want to propose skill or harness improvements based on review findings
- You want to review a plan's evidence artifacts for patterns worth preserving

Do NOT trigger this skill when:

- Work is still in progress (use Work-phase verification skills instead)
- You want to create a PR (use `pr-execution`)
- You want to run Voyager/macOS tests (use `voyager-dev`)
- You want to create or modify a skill (use `skill-creator`)
- You want to commit code or modify product files
