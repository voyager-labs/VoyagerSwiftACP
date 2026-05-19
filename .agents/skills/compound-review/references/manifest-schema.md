# Run Manifest Schema

**Version:** 2.0
**Path:** `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json`
**Family:** Run Manifest
**Source of truth:** Artifact Contract §Output 1

---

## Overview

The run manifest is a JSON artifact that enumerates every input consumed and output produced during a single compound-review run. It is the authoritative source for `run_id`, `plan_slug`, lineage, and stale-detection metadata. Downstream agents use the manifest to route findings, avoid stale reads, and resolve which run produced which output.

---

## Schema

```json
{
    "schema_version": "2.0",
    "run_id": "2026-04-10-181500",
    "plan_slug": "voy-208-grid-drop-interaction-stabilization",
    "run_at": "2026-04-10T18:15:00Z",
    "inputs": {
        "plan": {
            "path": ".sisyphus/plans/voy-208-grid-drop-interaction-stabilization.md",
            "plan_slug": "voy-208-grid-drop-interaction-stabilization"
        },
        "evidence_files": [".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/task-1-grid-drop-contract.txt", ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/task-5-grid-drop-evidence-index.txt"],
        "facets": {
            "f1": ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f1-plan-compliance.md",
            "f2": ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f2-code-quality.md",
            "f3": ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f3-manual-qa.md",
            "f4": ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f4-scope-fidelity.md"
        },
        "notepads": {
            "learnings": ".sisyphus/notepads/grid-drop-folder-thumbnail-ux-naturalization/learnings.md",
            "decisions": ".sisyphus/notepads/grid-drop-folder-thumbnail-ux-naturalization/decisions.md",
            "issues": ".sisyphus/notepads/grid-drop-folder-thumbnail-ux-naturalization/issues.md",
            "problems": ".sisyphus/notepads/grid-drop-folder-thumbnail-ux-naturalization/problems.md"
        }
    },
    "outputs": {
        "manifest": ".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/manifest.json",
        "findings": ".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/findings.json",
        "learning": ".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/learning.md",
        "skill_draft": ".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/skill-draft.md",
        "run_summary": ".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/run-summary.md"
    },
    "lineage": {
        "source_plan": ".sisyphus/plans/voy-208-grid-drop-interaction-stabilization.md",
        "source_evidence": [".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/task-1-grid-drop-contract.txt", ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/task-5-grid-drop-evidence-index.txt"],
        "source_facets": [".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f1-plan-compliance.md", ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f2-code-quality.md", ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f3-manual-qa.md", ".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f4-scope-fidelity.md"],
        "source_notepads": ["grid-drop-folder-thumbnail-ux-naturalization"]
    },
    "evidence_sources_consumed": {
        "for_findings": [".sisyphus/evidence/voy-208-grid-drop-interaction-stabilization/f1-plan-compliance.md"],
        "for_learning": [".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/findings.json"],
        "for_draft": [".sisyphus/reviews/voy-208-grid-drop-interaction-stabilization/2026-04-10-181500/findings.json"]
    },
    "schema_valid": true,
    "confidence_reduced": false,
    "facets_missing": [],
    "missing_sources": []
}
```

---

## Field Documentation

### Top-Level Fields

| Field                       | Type     | Required | Description                                                                          |
| --------------------------- | -------- | -------- | ------------------------------------------------------------------------------------ |
| `schema_version`            | string   | yes      | Fixed string `"2.0"`. Increment only on breaking changes.                            |
| `run_id`                    | string   | yes      | Unique run identifier. Format: `YYYY-MM-DD-HHMMSS`. Generated at invocation.         |
| `plan_slug`                 | string   | yes      | Case identifier. Extracted from plan filename without `.md`. Groups runs.            |
| `run_at`                    | string   | yes      | ISO-8601 timestamp of run start. Used for stale detection.                           |
| `inputs`                    | object   | yes      | Enumeration of all input artifacts actually found. Present even if degraded.         |
| `outputs`                   | object   | yes      | Enumeration of all output artifacts written by this run.                             |
| `lineage`                   | object   | yes      | Flat lists of source artifacts that contributed to this run.                         |
| `schema_valid`              | boolean  | yes      | `true` only after manifest and findings schemas pass validation.                     |
| `confidence_reduced`        | boolean  | no       | `true` if any optional input was missing or degraded. Emitted by degrade-gracefully. |
| `facets_missing`            | string[] | no       | List of facet IDs (`f1`, `f2`, etc.) that were not found.                            |
| `missing_sources`           | string[] | no       | List of artifact paths that were expected but not found (degrade case).              |
| `evidence_sources_consumed` | object   | yes      | Evidence actually used for findings, learning, and draft synthesis.                  |

---

### Inputs Object

| Field                       | Type     | Required | Description                                                               |
| --------------------------- | -------- | -------- | ------------------------------------------------------------------------- |
| `inputs.plan`               | object   | yes      | The completed plan file consumed. Always present (required input).        |
| `inputs.plan.path`          | string   | yes      | Exact path to the plan file.                                              |
| `inputs.plan.plan_slug`     | string   | yes      | Plan slug extracted from filename.                                        |
| `inputs.evidence_files`     | string[] | yes      | Sorted list of evidence file paths actually found. At least one required. |
| `inputs.facets`             | object   | yes      | Present facets keyed by facet ID. Empty object if none found.             |
| `inputs.facets.f1`          | string   | no       | Path to `f1-plan-compliance.md` if present.                               |
| `inputs.facets.f2`          | string   | no       | Path to `f2-code-quality.md` if present.                                  |
| `inputs.facets.f3`          | string   | no       | Path to `f3-manual-qa.md` if present.                                     |
| `inputs.facets.f4`          | string   | no       | Path to `f4-scope-fidelity.md` if present.                                |
| `inputs.notepads`           | object   | yes      | Present notepad files keyed by filename. Empty object if none found.      |
| `inputs.notepads.learnings` | string   | no       | Path to `learnings.md` if present.                                        |
| `inputs.notepads.decisions` | string   | no       | Path to `decisions.md` if present.                                        |
| `inputs.notepads.issues`    | string   | no       | Path to `issues.md` if present.                                           |
| `inputs.notepads.problems`  | string   | no       | Path to `problems.md` if present.                                         |

---

### Outputs Object

| Field                 | Type   | Required | Description                                              |
| --------------------- | ------ | -------- | -------------------------------------------------------- |
| `outputs.manifest`    | string | yes      | Exact path to this manifest file.                        |
| `outputs.findings`    | string | yes      | Exact path to `findings.json`.                           |
| `outputs.learning`    | string | yes      | Exact path to `learning.md`.                             |
| `outputs.skill_draft` | string | yes      | Exact path to `skill-draft.md`.                          |
| `outputs.run_summary` | string | no       | Exact path to `run-summary.md`. Omitted on failure runs. |

---

### Lineage Object

| Field                     | Type     | Required | Description                                    |
| ------------------------- | -------- | -------- | ---------------------------------------------- |
| `lineage.source_plan`     | string   | yes      | Path to the source plan file.                  |
| `lineage.source_evidence` | string[] | yes      | Full paths to evidence files consumed.         |
| `lineage.source_facets`   | string[] | yes      | Full paths to facet files consumed.            |
| `lineage.source_notepads` | string[] | yes      | Flat list of notepad directory slugs consumed. |

**Note:** v2 stores full evidence and facet paths in lineage so plan-scoped evidence remains unambiguous.

---

### Evidence Sources Consumed Object

| Field                                    | Type     | Required | Description                                                    |
| ---------------------------------------- | -------- | -------- | -------------------------------------------------------------- |
| `evidence_sources_consumed.for_findings` | string[] | yes      | Source artifacts actually used to synthesize `findings.json`.  |
| `evidence_sources_consumed.for_learning` | string[] | yes      | Source artifacts actually used to synthesize `learning.md`.    |
| `evidence_sources_consumed.for_draft`    | string[] | yes      | Source artifacts actually used to synthesize `skill-draft.md`. |

This differs from `inputs.*`: inputs enumerate what was found, while `evidence_sources_consumed` records what materially influenced each output.

---

## Stale Detection

If any `inputs.*.path` file has a last-modified timestamp after `run_at`, the manifest is stale. The skill must:

1. Write `.sisyphus/reviews/{plan_slug}/{run_id}/FAILURE.md` describing the stale condition.
2. Stop. Do not emit findings, learning, or draft.

---

## Example Payload (Minimal — Degrade Case)

```json
{
    "schema_version": "2.0",
    "run_id": "2026-04-10-181500",
    "plan_slug": "grid-drop-folder-thumbnail-ux-naturalization",
    "run_at": "2026-04-10T18:15:00Z",
    "inputs": {
        "plan": {
            "path": ".sisyphus/plans/grid-drop-folder-thumbnail-ux-naturalization.md",
            "plan_slug": "grid-drop-folder-thumbnail-ux-naturalization"
        },
        "evidence_files": [".sisyphus/evidence/grid-drop-folder-thumbnail-ux-naturalization/task-1-grid-drop-contract.txt"],
        "facets": {},
        "notepads": {}
    },
    "outputs": {
        "manifest": ".sisyphus/reviews/grid-drop-folder-thumbnail-ux-naturalization/2026-04-10-181500/manifest.json",
        "findings": ".sisyphus/reviews/grid-drop-folder-thumbnail-ux-naturalization/2026-04-10-181500/findings.json",
        "learning": ".sisyphus/reviews/grid-drop-folder-thumbnail-ux-naturalization/2026-04-10-181500/learning.md",
        "skill_draft": ".sisyphus/reviews/grid-drop-folder-thumbnail-ux-naturalization/2026-04-10-181500/skill-draft.md",
        "run_summary": ".sisyphus/reviews/grid-drop-folder-thumbnail-ux-naturalization/2026-04-10-181500/run-summary.md"
    },
    "lineage": {
        "source_plan": ".sisyphus/plans/grid-drop-folder-thumbnail-ux-naturalization.md",
        "source_evidence": [".sisyphus/evidence/grid-drop-folder-thumbnail-ux-naturalization/task-1-grid-drop-contract.txt"],
        "source_facets": [],
        "source_notepads": []
    },
    "schema_valid": true,
    "confidence_reduced": true,
    "facets_missing": ["f1", "f2", "f3", "f4"],
    "missing_sources": []
}
```

**Degraded fields noted:**

- `schema_valid`: schema validation passed even though optional inputs were absent.
- `facets_missing`: all four facets absent — confidence reduced.
- `facets` and `notepads` empty objects — degrade-gracefully applied.

---

## Schema Version History

| Version | Date       | Change                                                                                                                   |
| ------- | ---------- | ------------------------------------------------------------------------------------------------------------------------ |
| 1.0     | 2026-04-10 | Initial schema.                                                                                                          |
| 2.0     | 2026-05-17 | Artifact-family v3 layout: plan-scoped evidence, unified review run outputs, run_summary, and evidence_sources_consumed. |
