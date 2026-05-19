# Structured Review Findings Schema

**Version:** 2.0  
**Path:** `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json`  
**Family:** Structured Findings  
**Source of truth:** Artifact Contract §Output 2

---

## Overview

Findings are normalized, deduplicated issue records extracted from the review facets (`f1`–`f4`) and task evidence files. Each finding carries routing-friendly metadata (`severity`, `owner`, `action_class`) and a `dedupe_key` so downstream agents can act without re-parsing prose. Findings with the same `dedupe_key` are collapsed to a single representative record.

Findings are **immutable per run**: once written, they are not modified. A new run produces a new findings file.

---

## Schema

```json
{
    "schema_version": "2.0",
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
            "source_artifacts": [".sisyphus/evidence/{plan_slug}/f3-manual-qa.md", ".sisyphus/evidence/{plan_slug}/f1-plan-compliance.md"],
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
            "source_artifacts": [".sisyphus/evidence/{plan_slug}/f2-code-quality.md"],
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
            "source_artifacts": [".sisyphus/evidence/{plan_slug}/f2-code-quality.md"],
            "dedupe_key": "drag-option-flag-stale-after-copy",
            "verdict": "APPROVE"
        }
    ]
}
```

---

## Field Documentation

### Top-Level Fields

| Field             | Type     | Required | Description                                                             |
| ----------------- | -------- | -------- | ----------------------------------------------------------------------- |
| `schema_version`  | string   | yes      | Fixed string `"2.0"`.                                                   |
| `run_id`          | string   | yes      | Matches the run manifest's `run_id`.                                    |
| `plan_slug`       | string   | yes      | Matches the run manifest's `plan_slug`.                                 |
| `generated_at`    | string   | yes      | ISO-8601 timestamp of findings generation.                              |
| `facets_consumed` | string[] | yes      | Facet IDs that were present and read (`f1`, `f2`, etc.).                |
| `facets_missing`  | string[] | yes      | Facet IDs that were expected but not found. Empty if all present.       |
| `total_findings`  | integer  | yes      | Count of items in the `findings` array.                                 |
| `findings`        | object[] | yes      | Array of finding records. Empty array is valid (all findings approved). |

---

### Finding Record Fields

| Field              | Type     | Required | Description                                                                                                                        |
| ------------------ | -------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `id`               | string   | yes      | Unique per-run ID. Format: `FIND-{NNN}` (e.g., `FIND-001`, `FIND-002`).                                                            |
| `severity`         | string   | yes      | One of: `critical`, `high`, `medium`, `low`, `informational`.                                                                      |
| `owner`            | string   | yes      | Who can act on this finding. One of: `agent`, `human`, `orchestrator`.                                                             |
| `action_class`     | string   | yes      | What kind of action is needed. One of: `test-coverage`, `code-quality`, `design`, `scope`, `guardrail`.                            |
| `category`         | string   | yes      | Freeform topic tag for discovery and grouping. Lowercase hyphenated (e.g., `drag-option-lifecycle`).                               |
| `title`            | string   | yes      | Single-line summary. Imperative mood preferred (e.g., "Add test for X").                                                           |
| `description`      | string   | yes      | 1–3 sentence description of the finding. Plain text, no markdown formatting required.                                              |
| `source_artifacts` | string[] | yes      | Exact paths to artifacts that contributed this finding. Used for lineage and deduplication.                                        |
| `dedupe_key`       | string   | yes      | String that uniquely identifies the issue. Same key from different sources = duplicate. Lowercase hyphenated identifier preferred. |
| `verdict`          | string   | yes      | Final status. One of: `APPROVE`, `REJECT`, `CONDITIONAL`.                                                                          |

---

## Enumerated Value Reference

### severity

| Value           | Description                                                     |
| --------------- | --------------------------------------------------------------- |
| `critical`      | Bug or blocker with no workaround. Immediate action required.   |
| `high`          | Significant issue. Should be addressed before merge.            |
| `medium`        | Moderate issue. Addressed in follow-up or tracked as tech debt. |
| `low`           | Minor issue or observation. Note and monitor.                   |
| `informational` | Informational only. No action required but worth tracking.      |

### owner

| Value          | Description                                                           |
| -------------- | --------------------------------------------------------------------- |
| `agent`        | A downstream agent can act on this finding without human escalation.  |
| `human`        | Human review or decision required. Agent cannot act alone.            |
| `orchestrator` | The orchestrator should route or schedule this finding for attention. |

### action_class

| Value           | Description                                                |
| --------------- | ---------------------------------------------------------- |
| `test-coverage` | Gap in test coverage identified.                           |
| `code-quality`  | Code quality issue (style, complexity, duplication).       |
| `design`        | Design or architecture concern.                            |
| `scope`         | Scope creep or fidelity deviation detected.                |
| `guardrail`     | Guardrail violation detected (must-NOT-have check failed). |

### verdict

| Value         | Description                                                     |
| ------------- | --------------------------------------------------------------- |
| `APPROVE`     | Finding does not block. Approved as-is or observation only.     |
| `REJECT`      | Finding represents a defect that must be fixed before approval. |
| `CONDITIONAL` | Partially approved with conditions or follow-up requirements.   |

---

## Deduplication Rules

Two findings with the same `dedupe_key` are considered duplicates.

1. **Keep the one with more `source_artifacts`** (broader evidence base).
2. **If equal**, keep the one with higher `severity`.
3. **If still equal**, keep the first-written (lower `FIND-{NNN}` ID).
4. Emit a `collapsed_from` array in the surviving finding listing the duplicate IDs that were merged.

**Example collapsed finding:**

```json
{
    "id": "FIND-001",
    "severity": "high",
    "owner": "agent",
    "action_class": "test-coverage",
    "category": "regression-risk",
    "title": "acceptDrop success branches preserve drop highlight",
    "description": "All return-true branches in acceptDrop now defer highlight clearing. Verified in f3 manual QA.",
    "source_artifacts": [".sisyphus/evidence/{plan_slug}/f3-manual-qa.md", ".sisyphus/evidence/{plan_slug}/f1-plan-compliance.md"],
    "dedupe_key": "grid-drop-highlight-lifecycle-deferred-copy",
    "verdict": "APPROVE",
    "collapsed_from": ["FIND-007", "FIND-012"]
}
```

---

## Missing Sources (Degrade Case)

When the workflow degrades gracefully due to missing optional inputs, each finding MAY include a `missing_sources` array listing input paths that were expected but unavailable:

```json
{
    "id": "FIND-001",
    "severity": "high",
    "owner": "agent",
    "action_class": "test-coverage",
    "category": "regression-risk",
    "title": "...",
    "description": "...",
    "source_artifacts": [],
    "dedupe_key": "example-dedupe-key",
    "verdict": "CONDITIONAL",
    "missing_sources": [".sisyphus/evidence/{plan_slug}/f2-code-quality.md"]
}
```

The `missing_sources` field is **optional**. It is only present when the finding was produced under degraded confidence conditions.

---

## Example Payload: Mixed Verdict

```json
{
    "schema_version": "2.0",
    "run_id": "2026-04-10-181500",
    "plan_slug": "grid-drop-folder-thumbnail-ux-naturalization",
    "generated_at": "2026-04-10T18:15:00Z",
    "facets_consumed": ["f1", "f2"],
    "facets_missing": ["f3", "f4"],
    "total_findings": 2,
    "findings": [
        {
            "id": "FIND-001",
            "severity": "high",
            "owner": "human",
            "action_class": "code-quality",
            "category": "state-leak",
            "title": "Drop highlight persists after failed copy operation",
            "description": "When a copy operation fails silently, the drop highlight is not cleared. Found in f2 analysis.",
            "source_artifacts": [".sisyphus/evidence/{plan_slug}/f2-code-quality.md"],
            "dedupe_key": "drop-highlight-persists-after-failed-copy",
            "verdict": "REJECT",
            "missing_sources": [".sisyphus/evidence/{plan_slug}/f3-manual-qa.md"]
        },
        {
            "id": "FIND-002",
            "severity": "low",
            "owner": "agent",
            "action_class": "design",
            "category": "drag-option-lifecycle",
            "title": "Option drag flag not reset on cancelled session",
            "description": "Harmless: flag is reset on next willBeginAt. Informational only.",
            "source_artifacts": [".sisyphus/evidence/{plan_slug}/f2-code-quality.md"],
            "dedupe_key": "drag-option-flag-stale-after-cancel",
            "verdict": "APPROVE"
        }
    ]
}
```

---

## Schema Version History

| Version | Date       | Change                                                                                 |
| ------- | ---------- | -------------------------------------------------------------------------------------- |
| 1.0     | 2026-04-10 | Initial schema.                                                                        |
| 2.0     | 2026-05-17 | Aligned with manifest v2: evidence paths updated to plan-scoped, artifact-contract v2. |
