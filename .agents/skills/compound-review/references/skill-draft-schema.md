# Skill / Harness Draft Schema

**Version:** 1.1
**Path:** `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`
**Family:** Skill / Harness Draft
**Output type:** Future skill or harness proposal
**Source of truth:** Artifact Contract §Output 4

---

## Overview

The skill/harness draft is a Markdown artifact containing a concrete proposal for a future `.agents/skills/` or `.agents/rules/` improvement. It is **not** an executable skill — it is a structured recommendation with exact source findings, proposed scope, and rationale, requiring human review before adoption.

Drafts are **not auto-created**: they are emitted only when the review produces findings that justify a future skill or harness investment. If no findings meet the draft threshold, this output is still created but may be minimal or empty.

**Two draft subtypes:**

| Subtype       | Tag value   | Purpose                                                         |
| ------------- | ----------- | --------------------------------------------------------------- |
| **New Skill** | `new-skill` | Propose creating an entirely new skill under `.agents/skills/`. |
| **Rule**      | `rule`      | Propose creating or updating a rule under `.agents/rules/`.     |

The subtype is declared in the `Proposed Target` section.

---

## Document Structure

```
# Skill / Harness Draft — {plan_slug}

**Run:** {run_id}
**Generated:** {generated_at}
**Proposed Target:** {target-path} (new skill or rule, not yet created)

---

## Proposal: {proposal-title}

### Rationale

{Why this skill/harness is needed. Bounded to specific findings.}

### Source Findings

- `{FIND-NNN}` ({dedupe_key}) — from {facet(s)}
- `{FIND-NNN}` ({dedupe_key}) — from {facet(s)}

### Proposed Scope

- {What the skill/rules will do}
- {What files it will read}
- {What it will verify or enforce}

### Does NOT

- {What is explicitly out of scope}

### Target File

`{path to proposed skill or rule file}`

### Non-Goals

- {What other skills/systems handle}

### Readiness

{Draft status and what is needed for adoption.}

### Creation Justification

This proposal needs a distinct skill/rule because the finding recurs across multiple runs and cannot be captured as a short reference update to an existing skill.

### Source-Artifact Linkage

| Source Finding | Dedup Key | Severity | Issue |
| --------------- | --------- | -------- | ------ |
| `FIND-001`      | grid-drop-highlight-lifecycle-deferred-copy | high | Highlight clearing timing |
| `FIND-002`      | reducer-redundant-drag-option-persist | medium | Redundant state persist |
```

---

## Field Documentation

| Field                     | Required | Description                                                                                |
| ------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| `Proposal` (H2)           | yes      | The name of the proposed skill or rule.                                                    |
| `Rationale`               | yes      | 1–3 paragraph explanation of why this is needed, grounded in findings.                     |
| `Source Findings`         | yes      | Bulleted list of finding IDs with dedupe_keys and source facets.                           |
| `Proposed Scope`          | yes      | Bulleted list of what the skill/rules will do, read, and verify.                           |
| `Does NOT`                | no       | Bulleted list of what is explicitly out of scope for this proposal.                        |
| `Target File`             | yes      | Exact path to the proposed file (e.g., `.agents/skills/{proposed-skill-name}/SKILL.md`).   |
| `Non-Goals`               | yes      | Bulleted list of what other skills/systems handle (to avoid overlap).                      |
| `Readiness`               | yes      | Draft status. One of: `Draft only`, `Needs human review`, `Ready for adoption`, `Adopted`. |
| `Promotion Gate`          | yes      | Explicit recommendation: promote target, confidence, blast radius, prerequisites, and catch-next-time. |
| `Creation Justification`  | yes      | Why this is not simply an update to an existing skill/reference. If it can be absorbed, set `promote_to: none`. |
| `Source-Artifact Linkage` | yes      | Table linking each source finding to its dedupe_key, severity, and the issue it addresses. |

---

## Source-Artifact Linkage Table

The linkage table is the **machine-readable core** of the draft. It enables downstream agents (Task 5, Task 6) to route the draft to the correct skill/harness location and correlate it with the findings that motivated it.

| Column           | Description                                             |
| ---------------- | ------------------------------------------------------- |
| `Source Finding` | Finding ID (e.g., `FIND-001`).                          |
| `Dedup Key`      | The finding's `dedupe_key`.                             |
| `Severity`       | Finding severity (`critical`, `high`, `medium`, `low`). |
| `Issue`          | Short description of the issue this draft addresses.    |

---

## Draft Threshold

A skill/harness draft is **emitted** when at least one finding meets all of:

1. `verdict` is not `APPROVE` (i.e., the finding represents a problem), OR the finding is `APPROVE` but has `action_class` of `test-coverage` or `design` that could benefit from a harness.
2. `severity` is `medium` or higher.

OR when the operator explicitly requests a draft regardless of threshold.

---

## Example: New Skill Draft

```markdown
# Skill / Harness Draft — grid-drop-folder-thumbnail-ux-naturalization

**Run:** 2026-04-10-181500
**Generated:** 2026-04-10T18:15:00Z
**Proposed Target:** `.agents/skills/{proposed-skill-name}/` (new skill, not yet created)

---

## Proposal: Add grid-drop lifecycle verification skill

### Rationale

Repeated finding across f2 code quality reviews: coordinator drag/drop state clearing has multiple ownership risk. A dedicated harness skill could verify highlight lifecycle behavior on every grid-drop change before PR review, reducing the risk of regression in this area.

### Source Findings

- `FIND-001` (grid-drop-highlight-lifecycle-deferred-copy) — from f2 + f3
- `FIND-002` (reducer-redundant-drag-option-persist) — from f2

### Proposed Scope

- New skill: `.agents/skills/{proposed-skill-name}/SKILL.md`
- Reads: `EntryGridCoordinator+Extensions.swift`, `EntryViewLayoutAutoscrollAcceleration.swift`
- Verifies: single-owner highlight clearing, correct `shouldClearAfterSessionEnd` semantics
- Asserts that `acceptDrop` success branches do NOT call `setDropTargetEntryId(nil)` or `setDropTargeted(false)`
- Does NOT: mutate product code, run tests, create commits

### Does NOT

- Execute XCTest suites (the active Work-phase verification skill handles that)
- Create or modify PRs (pr-execution handles that)
- Trigger automatic Work loops

### Target File

`.agents/skills/{proposed-skill-name}/SKILL.md`

### Non-Goals

- No test execution (the active Work-phase verification skill handles that)
- No PR creation (pr-execution handles that)
- No automatic Work loops
- No cross-repo artifact resolution

### Readiness

Draft only. Requires human review before adoption.

### Promotion Gate

- promote_to: skill
- confidence: medium
- blast_radius: package
- prerequisites_met: no
- catch_next_time: Require explicit lifecycle branch verification before implementation.

### Source-Artifact Linkage

| Source Finding | Dedup Key                                   | Severity | Issue                                   |
| -------------- | ------------------------------------------- | -------- | --------------------------------------- |
| `FIND-001`     | grid-drop-highlight-lifecycle-deferred-copy | high     | Highlight clearing timing and ownership |
| `FIND-002`     | reducer-redundant-drag-option-persist       | medium   | Redundant state persist in reducer      |
```

---

## Example: Rule Draft

```markdown
# Skill / Harness Draft — grid-drop-folder-thumbnail-ux-naturalization

**Run:** 2026-04-10-181500
**Generated:** 2026-04-10T18:15:00Z
**Proposed Target:** `.agents/rules/drag-drop-state-ownership.rule` (new rule, not yet created)

---

## Proposal: Enforce single-owner highlight clearing in drag/drop coordinators

### Rationale

F1 and F2 findings confirm that multiple components (coordinator + reducer) both clearing highlight state causes premature visual cleanup. A rule should prevent future coordinators from falling into this pattern.

### Source Findings

- `FIND-001` (grid-drop-highlight-lifecycle-deferred-copy) — from f1 + f2

### Proposed Scope

- New rule: `.agents/rules/drag-drop-state-ownership.rule`
- Scans: `*Coordinator*Extensions.swift` files under `apps/macos/Voyager/`
- Enforces: No `setDropTargetEntryId(nil)` or `setDropTargeted(false)` in `acceptDrop` success branches
- Enforces: `shouldClearAfterSessionEnd` gating is present for session-end clearing

### Target File

`.agents/rules/drag-drop-state-ownership.rule`

### Non-Goals

- No rule for list-view coordinators (separate scope)
- No enforcement of file operation completion handling

### Readiness

Draft only. Requires human review before adoption.

### Promotion Gate

- promote_to: rule
- confidence: medium
- blast_radius: package
- prerequisites_met: no
- catch_next_time: Require explicit lifecycle branch verification before implementation.

### Source-Artifact Linkage

| Source Finding | Dedup Key                                   | Severity | Issue                                    |
| -------------- | ------------------------------------------- | -------- | ---------------------------------------- |
| `FIND-001`     | grid-drop-highlight-lifecycle-deferred-copy | high     | Multiple ownership of highlight clearing |
```

---

## Schema Version History

| Version | Date       | Change          |
| ------- | ---------- | --------------- |
| 1.0     | 2026-04-10 | Initial schema. |
| 1.1     | 2026-05-17 | Added Promotion Gate and Creation Justification. |
