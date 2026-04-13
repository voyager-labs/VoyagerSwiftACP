# Review Synthesis and Finding Routing Rules

**Version:** 1.0
**Scope:** Defines how the compound-review skill merges evidence from multiple input artifacts into normalized, deduplicated findings, assigns routing metadata, and orders the final output.
**Source of truth for:** Task 5 synthesis/routing logic. The skill shell (Task 4) delegates to these rules during the synthesis phase.
**Depends on:** `artifact-contract.md` (input families), `findings-schema.md` (output schema), `manifest-schema.md` (degrade metadata).

---

## 1. Overview

Synthesis is the phase where raw evidence from task logs, f1–f4 review facets, and notepad files is converted into a single `findings.json` with normalized, deduplicated records. This document specifies:

1. **Extraction precedence** — which artifact type wins when multiple sources describe the same issue.
2. **Deduplication** — deterministic collapse of duplicate findings by `dedupe_key`.
3. **Severity assignment** — how severity is assigned and when it is escalated.
4. **Owner and action_class routing** — deterministic assignment from source artifact type.
5. **Output ordering** — the required sort order of findings in the output array.
6. **Partial evidence mode** — behavior when some input artifacts are absent.

---

## 2. Extraction Phase

### 2.1 Source Artifact Types

The synthesis phase consumes four categories of input:

| Category          | Artifacts                                                                                | Evidence Weight                                    |
| ----------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
| **Facets**        | `f1-plan-compliance.md`, `f2-code-quality.md`, `f3-manual-qa.md`, `f4-scope-fidelity.md` | Primary — structured review output                 |
| **Task Evidence** | `task-{N}-{slug}.*` files                                                                | Supporting — per-task execution proof              |
| **Notepad**       | `learnings.md`, `decisions.md`, `issues.md`, `problems.md`                               | Contextual — operational context and known issues  |
| **Plan**          | The completed plan `.md` file                                                            | Structural — defines scope and acceptance criteria |

### 2.2 Extraction Order

Findings are extracted from artifacts in this fixed order. The order determines which `source_artifacts` are listed first but does not affect deduplication precedence (Section 3 handles that).

1. `f1-plan-compliance.md` — plan compliance issues, guardrail violations
2. `f2-code-quality.md` — code quality findings, anti-patterns
3. `f3-manual-qa.md` — manual verification results, behavioral findings
4. `f4-scope-fidelity.md` — scope creep, unexpected file changes
5. Task evidence files (sorted alphabetically by filename) — test results, execution logs
6. Notepad files (`issues.md` → `problems.md` → `decisions.md` → `learnings.md`) — unresolved issues, operational decisions

Each extracted observation becomes a **raw finding** with a provisional `dedupe_key`, `severity`, `owner`, `action_class`, `title`, `description`, and `source_artifacts` (the path of the artifact it was extracted from).

---

## 3. Deduplication and Merge Rules

Two raw findings with the same `dedupe_key` are considered duplicates and must be collapsed into a single representative finding.

### 3.1 Merge Algorithm

For each group of raw findings sharing the same `dedupe_key`:

1. **Merge `source_artifacts`:** Union of all `source_artifacts` arrays from every finding in the group. The surviving finding lists all contributing paths.
2. **Merge `description`:** Use the description from the finding with the highest-precedence source (Section 3.2). If descriptions differ substantively (different aspects of the same issue), concatenate with `; ` separator, citing each source.
3. **Select severity:** Highest severity among the group (Section 4).
4. **Select `id`:** Lowest `FIND-{NNN}` ID in the group.
5. **Emit `collapsed_from`:** Array of the other `FIND-{NNN}` IDs that were collapsed into the survivor.

### 3.2 Source Precedence for Merge Conflicts

When two findings with the same `dedupe_key` disagree on any field, this precedence order resolves the conflict. Higher precedence wins:

| Precedence  | Source                  | Rationale                                                                           |
| ----------- | ----------------------- | ----------------------------------------------------------------------------------- |
| 1 (highest) | `f1-plan-compliance.md` | Plan compliance and guardrail violations are authoritative for scope and acceptance |
| 2           | `f4-scope-fidelity.md`  | Scope fidelity is authoritative for scope boundary questions                        |
| 3           | `f3-manual-qa.md`       | Manual QA provides runtime-verified behavioral evidence                             |
| 4           | `f2-code-quality.md`    | Code quality analysis provides structural correctness evidence                      |
| 5           | Task evidence files     | Task evidence is supporting, not a review                                           |
| 6 (lowest)  | Notepad files           | Notepad entries are contextual, not structured review output                        |

When precedence is equal (same source type, e.g., two task evidence files), the file that comes first alphabetically wins.

### 3.3 dedupe_key Generation

The `dedupe_key` is a lowercase-hyphenated string that uniquely identifies the issue, not the source. Generation rules:

1. If the source artifact already assigns a `dedupe_key` (e.g., from a prior findings file), use it unchanged.
2. If the source artifact describes the issue in prose, synthesize the key from the **issue identity**: `{component}-{behavior}-{problem-pattern}`.
3. Two findings about the same root cause must share the same `dedupe_key` even if described differently. The synthesizer must normalize to the canonical form.
4. When unsure whether two findings describe the same issue, use **different** `dedupe_key` values. False negatives (two separate findings for the same issue) are acceptable in bounded cases; false positives (wrongly merged findings) are not.

### 3.4 Example Merge

**Raw findings before deduplication:**

| ID       | dedupe_key                                | Source             | Severity | Description                                             |
| -------- | ----------------------------------------- | ------------------ | -------- | ------------------------------------------------------- |
| FIND-003 | drop-highlight-persists-after-failed-copy | f2-code-quality.md | medium   | Redundant read-write in reducer                         |
| FIND-007 | drop-highlight-persists-after-failed-copy | f3-manual-qa.md    | high     | acceptDrop success branches do not clear isDropTargeted |
| FIND-012 | drop-highlight-persists-after-failed-copy | notepad/issues.md  | low      | Known: stale highlight after silent copy failure        |

**After merge:**

```json
{
    "id": "FIND-003",
    "severity": "high",
    "owner": "agent",
    "action_class": "code-quality",
    "category": "drag-drop-lifecycle",
    "title": "acceptDrop success branches preserve drop highlight",
    "description": "acceptDrop success branches do not clear isDropTargeted; redundant read-write in reducer noted",
    "source_artifacts": [".sisyphus/evidence/f2-code-quality.md", ".sisyphus/evidence/f3-manual-qa.md", ".sisyphus/notepads/grid-drop-folder-thumbnail-ux-naturalization/issues.md"],
    "dedupe_key": "drop-highlight-persists-after-failed-copy",
    "verdict": "APPROVE",
    "collapsed_from": ["FIND-007", "FIND-012"]
}
```

---

## 4. Severity Assignment Rules

### 4.1 Base Severity from Source

Each source artifact implies a base severity for the issues it identifies:

| Source Type            | Default Severity Range   | Notes                                                                             |
| ---------------------- | ------------------------ | --------------------------------------------------------------------------------- |
| `f1` (plan compliance) | `high`–`critical`        | Guardrail violations are always at least `high`; plan scope deviations are `high` |
| `f2` (code quality)    | `low`–`high`             | Anti-pattern findings start at `low`; logic errors escalate to `high`             |
| `f3` (manual QA)       | `medium`–`critical`      | Runtime behavioral issues start at `medium`; regressions escalate                 |
| `f4` (scope fidelity)  | `high`–`critical`        | Scope creep is always `high`; unauthorized changes are `critical`                 |
| Task evidence          | `informational`–`medium` | Test pass/fail is informational; missing coverage is `medium`                     |
| Notepad                | `low`–`medium`           | Known issues are `low`–`medium` depending on impact                               |

### 4.2 Severity Escalation Rules

Severity is **never downgraded** during merge. The highest severity among duplicates wins (Section 3.1 step 3).

Additional escalation triggers:

| Condition                                                    | Escalation                | Rationale                                                  |
| ------------------------------------------------------------ | ------------------------- | ---------------------------------------------------------- |
| Finding appears in 3+ distinct source artifacts              | +1 level (max `critical`) | Broad evidence base increases confidence the issue is real |
| Finding is a guardrail violation (`action_class: guardrail`) | Minimum `high`            | Guardrail violations are plan-level constraints            |
| Finding is a scope violation (`action_class: scope`)         | Minimum `high`            | Scope violations require human attention                   |
| Finding appears in `f4` with verdict `REJECT`                | Minimum `high`            | Scope rejection is always significant                      |
| Finding verdict is `REJECT` from any source                  | Minimum `medium`          | Rejected findings need attention                           |

Severity escalation is capped at `critical`. An `informational` finding escalated by 2 levels becomes `high` (skipping `medium` would be incorrect — escalation follows the enum order: `informational` → `low` → `medium` → `high` → `critical`).

### 4.3 Severity Enum Order

```
informational < low < medium < high < critical
```

Comparison is ordinal by position in this list.

---

## 5. Owner and Action Class Routing Rules

### 5.1 Owner Assignment

The `owner` field is assigned deterministically from the source artifact type and the nature of the finding:

| Rule | Owner          | Condition                                                                           |
| ---- | -------------- | ----------------------------------------------------------------------------------- |
| O1   | `human`        | Finding originates from `f1` and is a guardrail violation                           |
| O2   | `human`        | Finding originates from `f4` with verdict `REJECT`                                  |
| O3   | `human`        | Severity is `critical`                                                              |
| O4   | `orchestrator` | Finding originates from `f4` and is a scope advisory (verdict `CONDITIONAL`)        |
| O5   | `orchestrator` | Finding requires cross-agent coordination (multiple `action_class` values possible) |
| O6   | `agent`        | Default — all other findings                                                        |

Rules are evaluated top-to-bottom. The first matching rule wins. For merged findings, the rule from the highest-precedence source (Section 3.2) determines the owner.

### 5.2 Action Class Assignment

The `action_class` field is assigned from the primary source artifact:

| Primary Source | Default `action_class` | Exceptions                                                              |
| -------------- | ---------------------- | ----------------------------------------------------------------------- |
| `f1`           | `scope`                | Guardrail violations → `guardrail`                                      |
| `f2`           | `code-quality`         | Test coverage gaps → `test-coverage`; architectural concerns → `design` |
| `f3`           | `test-coverage`        | Behavioral regressions → `code-quality`                                 |
| `f4`           | `scope`                | Scope boundary questions → `design`                                     |
| Task evidence  | `test-coverage`        | Execution failures → `code-quality`                                     |
| Notepad        | `design`               | Known bugs → `code-quality`                                             |

For merged findings from multiple sources, the `action_class` from the highest-precedence source is used, unless a lower-precedence source provides a more specific `action_class` that better describes the finding. The following specificity order applies when the merge requires choosing:

```
guardrail > scope > test-coverage > code-quality > design
```

A more specific action class from a lower-precedence source can override a less specific one from a higher-precedence source. For example, if f1 says `scope` but f2 identifies the same issue as `guardrail`, the merged finding uses `guardrail`.

---

## 6. Output Ordering

The `findings` array in `findings.json` is ordered by these rules, applied in sequence. Ties are broken by the next rule.

| Sort Key       | Direction                                                           | Rule                                        |
| -------------- | ------------------------------------------------------------------- | ------------------------------------------- |
| `verdict`      | `REJECT` first, then `CONDITIONAL`, then `APPROVE`                  | Blockers before advisories before approvals |
| `severity`     | `critical` → `high` → `medium` → `low` → `informational`            | Higher severity first                       |
| `owner`        | `human` → `orchestrator` → `agent`                                  | Human-actionable first                      |
| `action_class` | `guardrail` → `scope` → `test-coverage` → `code-quality` → `design` | Higher urgency classes first                |
| `id`           | `FIND-001` → `FIND-002` → ...                                       | Stable tiebreaker (insertion order)         |

### 6.1 Output Ordering Example

| Final ID | Verdict     | Severity      | Owner        | Action Class  | Sort Position |
| -------- | ----------- | ------------- | ------------ | ------------- | ------------- |
| FIND-001 | REJECT      | critical      | human        | guardrail     | 1             |
| FIND-002 | REJECT      | high          | human        | scope         | 2             |
| FIND-003 | CONDITIONAL | high          | orchestrator | scope         | 3             |
| FIND-004 | APPROVE     | high          | agent        | test-coverage | 4             |
| FIND-005 | APPROVE     | medium        | agent        | code-quality  | 5             |
| FIND-006 | APPROVE     | low           | agent        | design        | 6             |
| FIND-007 | APPROVE     | informational | agent        | design        | 7             |

---

## 7. Partial Evidence Mode

### 7.1 When Partial Evidence Mode Activates

Partial evidence mode activates when one or more optional input artifacts are absent. This is the **degrade-gracefully** behavior defined in the artifact contract.

Required inputs that are missing cause **report-and-stop** (not partial mode). Required inputs are:

- The completed plan file
- At least one task evidence file

Optional inputs whose absence triggers partial mode:

- Any of `f1`–`f4` facets
- Any notepad files

### 7.2 Partial Evidence Behavior

When in partial evidence mode:

1. **Set `confidence_reduced: true`** in the manifest.
2. **Set `facets_missing`** to the list of absent facet IDs (e.g., `["f3", "f4"]`).
3. **Set `missing_sources`** in the manifest to the list of expected-but-absent artifact paths.
4. **For each finding that would have been informed by a missing source**, add a `missing_sources` array to that finding listing the paths that were unavailable.
5. **Do NOT infer** what a missing source would have said. Only emit findings grounded in artifacts that were actually present.
6. **Emit a synthetic informational finding** (see Section 7.3) documenting the degraded state.

### 7.3 Degradation Metadata Finding

When in partial evidence mode, the synthesizer emits one additional finding at the end of the findings array:

```json
{
    "id": "FIND-{NNN}",
    "severity": "informational",
    "owner": "human",
    "action_class": "design",
    "category": "synthesis-metadata",
    "title": "Partial evidence mode: {N} sources unavailable",
    "description": "Run produced findings with reduced confidence. Missing sources: {comma-separated list}. Findings may lack coverage from {missing facet focus areas}.",
    "source_artifacts": [],
    "dedupe_key": "synthesis-partial-evidence-{run_id}",
    "verdict": "CONDITIONAL",
    "missing_sources": ["{list of all missing artifact paths}"]
}
```

This finding is always `informational` severity, `human` owner (because a human should decide whether to rerun after missing sources are produced), and `CONDITIONAL` verdict.

### 7.4 Facet Focus Areas (for Missing Source Description)

Each facet has a distinct review focus. When that facet is missing, findings may lack coverage in that area:

| Missing Facet | Missing Coverage Area                                               |
| ------------- | ------------------------------------------------------------------- |
| `f1`          | Plan compliance, acceptance criteria verification, guardrail checks |
| `f2`          | Code quality, anti-pattern detection, TCA pattern correctness       |
| `f3`          | Runtime behavioral verification, manual QA confirmation             |
| `f4`          | Scope fidelity, unauthorized file changes, boundary checks          |

### 7.5 Notepad Absence

When notepad files are absent:

- **No notepad at all:** Add `missing_sources` to the manifest listing expected notepad paths. Continue with warning. No `missing_sources` on individual findings (notepad is contextual, not a finding source).
- **Partial notepad (some files present):** Consume what is present. No additional metadata needed on findings. The manifest records which notepad files were consumed.

---

## 8. Verdict Assignment

The `verdict` field on each finding is determined by:

| Condition                                                   | Verdict                                 |
| ----------------------------------------------------------- | --------------------------------------- |
| Finding is a guardrail violation                            | `REJECT`                                |
| Finding severity is `critical`                              | `REJECT`                                |
| Finding has `missing_sources` (partial evidence)            | `CONDITIONAL` (unless already `REJECT`) |
| Finding is an observation or advisory with no action needed | `APPROVE`                               |
| Default for actionable but non-blocking findings            | `APPROVE`                               |

When merged findings disagree on verdict, the most restrictive verdict wins:

```
REJECT > CONDITIONAL > APPROVE
```

---

## 9. Synthesis Process Summary

The synthesis phase executes these steps in order:

1. **Gather inputs:** Read all present artifacts per the manifest. Record absent artifacts.
2. **Extract raw findings:** Process each artifact in extraction order (Section 2.2), generating raw findings with provisional metadata.
3. **Group by dedupe_key:** Bucket all raw findings by their `dedupe_key`.
4. **Merge duplicates:** For each group, apply merge rules (Section 3.1), selecting the representative finding using precedence (Section 3.2).
5. **Assign severity:** Apply base severity from source (Section 4.1), then escalate per rules (Section 4.2).
6. **Assign owner:** Apply owner rules top-to-bottom (Section 5.1).
7. **Assign action_class:** Apply action class from primary source with specificity override (Section 5.2).
8. **Assign verdict:** Apply verdict rules (Section 8).
9. **Handle partial evidence:** If any optional source is missing, emit degradation metadata (Section 7).
10. **Order findings:** Sort the final array by output ordering rules (Section 6).
11. **Assign final IDs:** Re-number findings sequentially from `FIND-001` in output order. Update `collapsed_from` references to use original pre-merge IDs (these are internal; the collapsed IDs are not renumbered).

---

## 10. Constraints

- **No inference on missing content.** If a source is absent, the synthesizer does not guess what it would have contained.
- **No fuzzy matching on dedupe_key.** dedupe_key comparison is exact string equality.
- **No dynamic severity inflation.** Escalation rules are the only mechanism to increase severity. There is no heuristic or LLM-based severity adjustment.
- **Deterministic output.** Given the same input artifact set, the synthesis phase must produce the same findings.json every time. All decisions are rule-based.
- **Merge never loses evidence.** The `source_artifacts` union ensures every contributing artifact is cited. The `collapsed_from` array preserves the original finding IDs.

---

## Schema Version History

| Version | Date       | Change           |
| ------- | ---------- | ---------------- |
| 1.0     | 2026-04-10 | Initial version. |
