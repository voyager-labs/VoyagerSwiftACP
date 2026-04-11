# Artifact Contract — Review → Compound Workflow

**Version:** 1.0  
**Scope:** Local-repo-only, manual-trigger, post-Work Review → Compound synthesis  
**Location:** `.agents/skills/compound-review/references/artifact-contract.md`

---

## Overview

This contract defines the authoritative input set, output set, path structure, lineage fields, and failure rules for the Review → Compound workflow. It is the source of truth for all artifact families consumed or emitted by this workflow. No cross-repo abstractions, databases, or undocumented external state apply in v1.

The workflow is **post-Work only** and **manual-trigger only**. It reads completed `.sisyphus` artifacts, emits structured findings, compound learnings, and skill/harness draft proposals. It never re-plans, mutates product code, or triggers automatic Work loops.

---

## Input Artifacts

### Required Inputs

| Family             | Path Pattern                           | Description                                                                                                                                                      |
| ------------------ | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Completed Plan** | `.sisyphus/plans/{plan-name}.md`       | A single plan that has reached completion (all TODOs checked or explicitly closed). The plan slug is the case identifier.                                        |
| **Task Evidence**  | `.sisyphus/evidence/task-{N}-{slug}.*` | Per-task evidence logs (`.md`, `.txt`, `.log`, `.json`) produced during plan execution. Naming: `task-{N}-{slug}.{ext}`. At least one evidence file is required. |

### Optional Inputs

| Family                  | Path Pattern                                                                                                                                                         | Condition                                                                                                                                                                                                                                                                 |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Final Review Facets** | `.sisyphus/evidence/f1-plan-compliance.md`, `.sisyphus/evidence/f2-code-quality.md`, `.sisyphus/evidence/f3-manual-qa.md`, `.sisyphus/evidence/f4-scope-fidelity.md` | `f1`..`f4` are the final review bundle. They are optional in v1. The filenames are stable and slug-independent: `f1-plan-compliance.md`, `f2-code-quality.md`, `f3-manual-qa.md`, `f4-scope-fidelity.md`. Presence is detected by exact filename match, not by plan slug. |
| **Notepad Files**       | `.sisyphus/notepads/{plan-name}/learnings.md`                                                                                                                        | Optional but strongly recommended. If present, the entire notepad family is consumed: `learnings.md`, `decisions.md`, `issues.md`, `problems.md`.                                                                                                                         |
| **Notepad Files**       | `.sisyphus/notepads/{plan-name}/decisions.md`                                                                                                                        | Optional. Consumed as part of the notepad family.                                                                                                                                                                                                                         |
| **Notepad Files**       | `.sisyphus/notepads/{plan-name}/issues.md`                                                                                                                           | Optional. Consumed as part of the notepad family.                                                                                                                                                                                                                         |
| **Notepad Files**       | `.sisyphus/notepads/{plan-name}/problems.md`                                                                                                                         | Optional. Consumed as part of the notepad family. Records unresolved issues and technical debt.                                                                                                                                                                           |

### Input Field Reference

| Field                   | Type     | Description                                                                               |
| ----------------------- | -------- | ----------------------------------------------------------------------------------------- |
| `plan_slug`             | string   | Identifies the case. Extracted from the plan filename (`{plan-name}` without `.md`).      |
| `run_id`                | string   | A unique run identifier. In v1, use the execution timestamp string (`YYYY-MM-DD-HHMMSS`). |
| `evidence_files`        | string[] | List of evidence file paths actually found, sorted alphabetically.                        |
| `facets_present`        | string[] | List of f1-f4 facets actually present (`f1`, `f2`, etc.).                                 |
| `notepad_dir`           | string   | Path to the matching notepad directory (`.sisyphus/notepads/{plan_slug}/`).               |
| `notepad_files_present` | string[] | List of notepad files found (`learnings.md`, `decisions.md`, `issues.md`, `problems.md`). |

---

## Output Artifacts

All outputs are **run-scoped**: they live under a run directory named by `{plan_slug}/{run_id}`.

### Run Directory Structure

```
.sisyphus/reviews/{plan_slug}/{run_id}/       ← run root
.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json
.sisyphus/reviews/{plan_slug}/{run_id}/findings.json
.sisyphus/compound/{plan_slug}/{run_id}/     ← compound outputs root
.sisyphus/compound/{plan_slug}/{run_id}/learning.md
.sisyphus/drafts/{plan_slug}/{run_id}/       ← skill/harness draft root
.sisyphus/drafts/{plan_slug}/{run_id}/skill-draft.md
```

### Output 1: Run Manifest

**Path:** `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json`

**Purpose:** Enumerates every artifact consumed and emitted in this run. Enables stale/mixed-run detection by comparing `plan_slug` and `run_id` fields across invocations.

```json
{
    "schema_version": "1.0",
    "run_id": "2026-04-10-181500",
    "plan_slug": "voy-208-grid-drop-interaction-stabilization",
    "run_at": "2026-04-10T18:15:00Z",
    "inputs": {
        "plan": {
            "path": ".sisyphus/plans/voy-208-grid-drop-interaction-stabilization.md",
            "plan_slug": "voy-208-grid-drop-interaction-stabilization"
        },
        "evidence_files": [".sisyphus/evidence/task-1-grid-drop-contract.txt", ".sisyphus/evidence/task-5-grid-drop-evidence-index.txt"],
        "facets": {
            "f1": ".sisyphus/evidence/f1-plan-compliance.md",
            "f2": ".sisyphus/evidence/f2-code-quality.md",
            "f3": ".sisyphus/evidence/f3-manual-qa.md",
            "f4": ".sisyphus/evidence/f4-scope-fidelity.md"
        },
        "notepads": {
            "learnings": ".sisyphus/notepads/grid-drop-folder-thumbnail-ux-naturalization/learnings.md",
            "decisions": ".sisyphus/notepads/grid-drop-folder-thumbnail-ux-naturalization/decisions.md"
        }
    },
    "outputs": {
        "manifest": ".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/manifest.json",
        "findings": ".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/findings.json",
        "learning": ".sisyphus/compound/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/learning.md",
        "skill_draft": ".sisyphus/drafts/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/skill-draft.md"
    },
    "lineage": {
        "source_plan": ".sisyphus/plans/voy-208-grid-drop-interaction-stabilization.md",
        "source_evidence": ["task-1-grid-drop-contract.txt", "task-5-grid-drop-evidence-index.txt"],
        "source_facets": ["f1-plan-compliance.md", "f2-code-quality.md", "f3-manual-qa.md", "f4-scope-fidelity.md"],
        "source_notepads": ["grid-drop-folder-thumbnail-ux-naturalization"]
    }
}
```

**Lineage Fields:**

| Field              | Purpose                                                                               |
| ------------------ | ------------------------------------------------------------------------------------- |
| `run_id`           | Uniquely identifies this run. Same case + same run_id = same inputs expected.         |
| `plan_slug`        | Groups runs by case. Allows cross-run deduplication.                                  |
| `inputs.*.path`    | Exact source artifact paths. Used to detect stale reads (plan modified after run_id). |
| `outputs.*.path`   | Exact output artifact paths.                                                          |
| `lineage.source_*` | Flat list of all input artifacts that contributed to this run.                        |

**Stale Detection Rule:** If any `inputs.*.path` file has a last-modified timestamp after the `run_at` timestamp in the manifest, the manifest is stale. The skill must report and stop — it may not silently re-read artifacts from a different run.

---

### Output 2: Structured Review Findings

**Path:** `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json`

**Purpose:** Normalized, deduplicated findings extracted from f1-f4 facets and evidence files. Each finding has routing-friendly metadata so downstream agents can act without re-parsing prose.

```json
{
    "schema_version": "1.0",
    "run_id": "2026-04-10-181500",
    "plan_slug": "voy-208-grid-drop-interaction-stabilization",
    "generated_at": "2026-04-10T18:15:00Z",
    "facets_consumed": ["f1", "f2", "f3", "f4"],
    "facets_missing": [],
    "total_findings": 3,
    "findings": [
        {
            "id": "FIND-001",
            "severity": "high",
            "owner": "agent",
            "action_class": "test-coverage",
            "category": "regression-risk",
            "title": "acceptDrop success branches preserve drop highlight",
            "description": "All return-true branches in acceptDrop now defer highlight clearing. Verified in f3 manual QA.",
            "source_artifacts": [".sisyphus/evidence/f3-manual-qa.md", ".sisyphus/evidence/f1-plan-compliance.md"],
            "dedupe_key": "grid-drop-highlight-lifecycle-deferred-copy",
            "verdict": "APPROVE"
        },
        {
            "id": "FIND-002",
            "severity": "medium",
            "owner": "agent",
            "action_class": "code-quality",
            "category": "maintainability",
            "title": "Redundant saveDragWithOption read-write in reducer",
            "description": "saveDragPaths handler reads and writes back the same value. Harmless but unnecessary.",
            "source_artifacts": [".sisyphus/evidence/f2-code-quality.md"],
            "dedupe_key": "reducer-redundant-drag-option-persist",
            "verdict": "APPROVE"
        },
        {
            "id": "FIND-003",
            "severity": "low",
            "owner": "agent",
            "action_class": "design",
            "category": "drag-option-lifecycle",
            "title": "Option flag not reset for deferred copy operations",
            "description": "When endedAt returns early for .copy, saveDragWithOption(false) is never called. Harmless but worth noting.",
            "source_artifacts": [".sisyphus/evidence/f2-code-quality.md"],
            "dedupe_key": "drag-option-flag-stale-after-copy",
            "verdict": "APPROVE"
        }
    ]
}
```

**Finding Fields:**

| Field              | Required | Description                                                                           |
| ------------------ | -------- | ------------------------------------------------------------------------------------- |
| `id`               | yes      | Unique per-run ID in format `FIND-{NNN}`                                              |
| `severity`         | yes      | `critical`, `high`, `medium`, `low`, `informational`                                  |
| `owner`            | yes      | Who can act: `agent`, `human`, `orchestrator`                                         |
| `action_class`     | yes      | What kind of action: `test-coverage`, `code-quality`, `design`, `scope`, `guardrail`  |
| `category`         | yes      | Freeform topic tag for discovery                                                      |
| `title`            | yes      | Single-line summary                                                                   |
| `description`      | yes      | 1-3 sentence description                                                              |
| `source_artifacts` | yes      | Array of exact artifact paths that contributed this finding                           |
| `dedupe_key`       | yes      | String that identifies the issue. Same dedupe_key from different sources = duplicate. |
| `verdict`          | yes      | Final status: `APPROVE`, `REJECT`, `CONDITIONAL`                                      |

**Deduplication:** Two findings with the same `dedupe_key` are the same issue. Keep the one with more `source_artifacts` (broader evidence). If equal, keep the one with higher severity. Emit a note in the finding that it was collapsed from multiple sources.

---

### Output 3: Compound Learning Document

**Path:** `.sisyphus/compound/{plan_slug}/{run_id}/learning.md`

**Purpose:** Reusable operational knowledge extracted from the run. Structured as guidance, not a run diary. Must include applicability, pattern to follow, and lineage to source artifacts.

```markdown
# Compound Learning — {plan_slug}

**Run:** {run_id}  
**Generated:** {generated_at}  
**Lineage:** {lineage.source_plan}

---

## Category: drag-drop-lifecycle

### When to defer drop-highlight clearing

**Applies when:**

- Grid drag/drop session where `.copy` is the detected operation
- Coordinator-based AppKit drag/drop with TCA state
- Highlight must persist until file operation completes

**Guidance:**

- Do NOT call `setDropTargetEntryId(nil)` or `setDropTargeted(false)` in `acceptDrop` success branches
- Use `shouldClearAfterSessionEnd(operation:)` to gate session-end clearing
- Return `false` for `.copy`, `true` for `.move` and empty operations
- Persist option drag state at `willBeginAt:` and reset at `endedAt:`

**Source:** findings `FIND-001`, `FIND-003`; notepad `decisions.md` (2026-04-09 session-local validated destination)

---

## Category: coordinator-state-ownership

### Single owner for highlight clearing

**Applies when:**

- Coordinator + reducer both manage visual state for drag/drop
- Risk of dual clearing causing premature highlight removal

**Guidance:**

- Exactly one owner responsible for clearing highlight on success
- `performDragOperation` success branches must NOT clear state
- Session-end handler (gated by rule set) is the single owner
- Reload safety net clears all targets in `rebuildSectionsAndReload`

**Source:** findings `FIND-001`; f1 plan compliance audit

---

## Overlap/Deduplication Note

This learning document was generated from findings that were deduplicated against prior compound artifacts using the `dedupe_key` field. If prior compound artifacts for the same `plan_slug` exist, merge by `category` and note which `run_id` each guidance came from.
```

---

### Output 4: Skill / Harness Draft Document

**Path:** `.sisyphus/drafts/{plan_slug}/{run_id}/skill-draft.md`

**Purpose:** A concrete proposal for a future `.agents/skills/` or `.agents/rules/` improvement, with exact source findings, target scope, and rationale. Does NOT auto-modify any skill or rule file.

```markdown
# Skill / Harness Draft — {plan_slug}

**Run:** {run_id}  
**Generated:** {generated_at}  
**Proposed Target:** `.agents/skills/grid-drop-harness/` (new skill, not yet created)

---

## Proposal: Add grid-drop lifecycle verification skill

### Rationale

Repeated finding across f2 code quality reviews: coordinator drag/drop state clearing has multiple ownership risk. A dedicated harness skill could verify highlight lifecycle behavior on every grid-drop change before PR review.

### Source Findings

- `FIND-001` (grid-drop-highlight-lifecycle-deferred-copy) — from f2 + f3
- `FIND-002` (reducer-redundant-drag-option-persist) — from f2

### Proposed Scope

- New skill: `.agents/skills/grid-drop-harness/SKILL.md`
- Reads: `EntryGridCoordinator+Extensions.swift`, `EntryViewLayoutAutoscrollAcceleration.swift`
- Verifies: single-owner highlight clearing, correct `shouldClearAfterSessionEnd` semantics
- Does NOT: mutate product code, run tests, create commits

### Target File

`.agents/skills/grid-drop-harness/SKILL.md`

### Non-Goals

- No test execution (test-runner handles that)
- No PR creation (pr-execution handles that)
- No automatic Work loops

### Readiness

Draft only. Requires human review before adoption.
```

---

## Failure Rules

### Bounded Failure Table

| Condition                                                                              | Behavior                                                                                                                                                                                                                                                               | Confidence                                    |
| -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **Missing plan**                                                                       | Report-and-stop. No defaulting to a different plan.                                                                                                                                                                                                                    | N/A — workflow cannot proceed without a plan. |
| **Missing all evidence**                                                               | Report-and-stop. At least one evidence file is required.                                                                                                                                                                                                               | N/A — no synthesis substrate.                 |
| **Some `f1`..`f4` missing**                                                            | Degrade-gracefully. Emit `facets_missing` metadata in findings. Adjust severity upwards for issues only detectable from missing facet. Facet presence is detected by exact stable filename (e.g., `f1-plan-compliance.md`), not by slug. Do not infer missing content. | Reduced — some findings may be absent.        |
| **Stale lineage** (plan file modified after run_id timestamp)                          | Report-and-stop. Do not re-emit outputs with stale timestamps.                                                                                                                                                                                                         | N/A — lineage integrity violated.             |
| **Partial notepad presence**                                                           | Degrade-gracefully. Proceed if at least one of `learnings.md` or `decisions.md` exists. If neither exists, note in manifest and continue without notepad consumption.                                                                                                  | Reduced — notepad insights unavailable.       |
| **No notepad at all**                                                                  | Continue with warning in manifest. Findings still emitted.                                                                                                                                                                                                             | Standard — notepads are optional inputs.      |
| **Mixed-run detection** (same plan_slug, different run_id, overlapping artifact paths) | Report-and-stop. The prior run's outputs may be stale. Human must resolve.                                                                                                                                                                                             | N/A — potential data corruption.              |

### Failure Action Definitions

- **Report-and-stop:** Emit a failure artifact at `.sisyphus/reviews/{plan_slug}/{run_id}/FAILURE.md` describing the condition, then halt. Do not emit findings/learning/draft.
- **Degrade-gracefully:** Proceed with reduced confidence. Add `confidence_reduced: true` to manifest and `missing_sources` list to findings. Do not guess at missing content.

### Replanning / Continuation

The workflow **must not** re-plan, trigger `/start-work`, or loop into Work. Any failure that would require new work must be reported-and-stopped. The operator (human) decides next steps.

---

## Path Reference Summary

| Element                   | Path                                                   |
| ------------------------- | ------------------------------------------------------ |
| Review outputs root       | `.sisyphus/reviews/{plan_slug}/{run_id}/`              |
| Compound outputs root     | `.sisyphus/compound/{plan_slug}/{run_id}/`             |
| Skill/harness drafts root | `.sisyphus/drafts/{plan_slug}/{run_id}/`               |
| Run manifest              | `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json` |
| Structured findings       | `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json` |
| Compound learning         | `.sisyphus/compound/{plan_slug}/{run_id}/learning.md`  |
| Skill/harness draft       | `.sisyphus/drafts/{plan_slug}/{run_id}/skill-draft.md` |
| Failure artifact          | `.sisyphus/reviews/{plan_slug}/{run_id}/FAILURE.md`    |

---

## Schema Versions

| Schema          | Version | Description                                                           |
| --------------- | ------- | --------------------------------------------------------------------- |
| `manifest.json` | `1.0`   | Initial. Contains inputs, outputs, lineage.                           |
| `findings.json` | `1.0`   | Initial. Severity, owner, action_class, source artifacts, dedupe key. |
