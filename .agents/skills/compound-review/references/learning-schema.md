# Compound Learning Document Schema

**Version:** 1.0
**Path:** `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`
**Family:** Compound Learning
**Output type:** Reusable operational knowledge
**Source of truth:** Artifact Contract §Output 3

---

## Overview

The compound learning document is a Markdown artifact containing reusable operational knowledge extracted from the review run. It is **not** a run diary — it is guidance structured for future planning cycles and agent decision-making. Each learning entry has clear applicability rules, the pattern to follow, and lineage to source artifacts.

**Two distinct learning types are emitted in this document:**

| Type                 | Tag value          | Downstream use                                                 |
| -------------------- | ------------------ | -------------------------------------------------------------- |
| **Bug Resolution**   | `bug-resolution`   | Future agents fix the same or similar bug correctly.           |
| **Harness Guidance** | `harness-guidance` | Future agents follow the pattern when writing tests/harnesses. |

Both types share the same document structure but differ in their `type` tag and the `applies_when` / `guidance` framing.

---

## Document Structure

```
# Compound Learning — {plan_slug}

**Run:** {run_id}
**Generated:** {generated_at}
**Lineage:** {lineage.source_plan}

---

## Category: {category-slug}

### {learning-title}

**Type:** {bug-resolution | harness-guidance}
**Tags:** [{tag-1}, {tag-2}]
**Applies when:**

- {condition 1}
- {condition 2}

**Guidance:**

- {rule or pattern to follow}
- {rule or pattern to avoid}

**Source:** {findings or facets that generated this learning}

---

## Category: {next-category-slug}

...
```

---

## Learning Entry Fields

| Field            | Required | Description                                                                                 |
| ---------------- | -------- | ------------------------------------------------------------------------------------------- |
| `Category`       | yes      | H2 section header. Format: `Category: {category-slug}`. Groups related learnings.           |
| `learning-title` | yes      | H3 section. The title of this learning entry.                                               |
| `Type`           | yes      | One of: `bug-resolution` or `harness-guidance`. Declared inline in bold.                    |
| `Tags`           | yes      | Array of lowercase hyphenated tags. Enables cross-run discovery and programmatic filtering. |
| `Applies when`   | yes      | Bulleted list of concrete conditions under which this guidance applies.                     |
| `Guidance`       | yes      | Bulleted list of do/don't rules or patterns to follow.                                      |
| `Source`         | yes      | Lineage reference: findings IDs and/or facet filenames.                                     |
| `Plan Feedback`  | yes      | What the next plan should do differently because of this learning.                          |
| `Catch Earlier`  | yes      | Which earlier phase could have caught the issue and how.                                    |
| `Reusability`    | yes      | `reusable` or `one-off`; distinguishes promotion candidates from case-local notes.          |
| `Promotion`      | yes      | `promote-to-skill: yes/no`, `promote-to-rule: yes/no`.                                      |
| `Confidence`     | yes      | `low`, `medium`, or `high`.                                                                 |
| `Blast Radius`   | yes      | `local`, `package`, or `repo-wide`.                                                         |

**Note:** `Tags` is required. Even if only one tag applies, it must be present as an array (minimum one element).

---

## Category Field

The `category` field is a lowercase hyphenated slug used for grouping and discovery. Suggested categories:

| Category slug                 | Use for                                                  |
| ----------------------------- | -------------------------------------------------------- |
| `drag-drop-lifecycle`         | Drop highlight clearing timing and ownership.            |
| `coordinator-state-ownership` | Which component owns which visual state.                 |
| `drag-option-lifecycle`       | Option-drag flag persistence across sessions.            |
| `test-pattern`                | TCA test patterns, TestStore usage.                      |
| `reducer-pattern`             | Reducer structure, action scoping, dependency injection. |
| `scope-fidelity`              | Staying within the approved scope in changes.            |

Categories are not formally enforced — they are freeform discovery tags. The author picks or invents category slugs as needed.

---

## Type Distinction: Bug Resolution vs. Harness Guidance

### Bug Resolution (`bug-resolution`)

**Purpose:** Encodes the correct fix for a bug that was identified and resolved.

**Framing:**

- `Applies when:` preconditions that would reproduce the bug
- `Guidance:` the correct behavior to follow; what to do instead of the buggy pattern

**Example:** "When `.copy` is the detected operation, do NOT clear highlight in `acceptDrop` success branches."

### Harness Guidance (`harness-guidance`)

**Purpose:** Encodes a reusable test or verification pattern that future agents should follow.

**Framing:**

- `Applies when:` situations where this test pattern should be applied
- `Guidance:` how to write the test/harness; what to verify and how

**Example:** "When verifying drop highlight lifecycle, use `shouldClearAfterSessionEnd(operation:)` to gate session-end clearing and assert that highlight persists through a `.copy` operation."

---

## Bug Resolution Example

```markdown
## Category: drag-drop-lifecycle

### When to defer drop-highlight clearing

**Type:** bug-resolution
**Tags:** [drag-drop-lifecycle, coordinator-state-ownership, tca-pattern]
**Applies when:**

- Grid drag/drop session where `.copy` is the detected operation
- Coordinator-based AppKit drag/drop with TCA state
- Highlight must persist until file operation completes

**Guidance:**

- Do NOT call `setDropTargetEntryId(nil)` or `setDropTargeted(false)` in `acceptDrop` success branches
- Use `shouldClearAfterSessionEnd(operation:)` to gate session-end clearing
- Return `false` for `.copy`, `true` for `.move` and empty operations
- Persist option drag state at `willBeginAt:` and reset at `endedAt:`

**Source:** findings `FIND-001`, `FIND-003`; f1 plan compliance audit
**Plan Feedback:** Include explicit drag lifecycle branch checks in future plans.
**Catch Earlier:** Plan review could require distinct copy/move/cancel QA scenarios.
**Reusability:** reusable
**Promotion:** promote-to-skill: no, promote-to-rule: yes
**Confidence:** high
**Blast Radius:** package
```

---

## Harness Guidance Example

```markdown
## Category: test-pattern

### Verify drop highlight lifecycle with deferred clearing

**Type:** harness-guidance
**Tags:** [tca-test-pattern, drag-drop-lifecycle, test-coverage, coordinator-state]
**Applies when:**

- Writing tests for grid drop highlight lifecycle
- The implementation uses `shouldClearAfterSessionEnd(operation:)` to gate session-end clearing
- Copy operations must NOT clear highlight at `acceptDrop` time

**Guidance:**

- Send `.view(.setDropTargeted(true))` and `.routing(.handleDrop(...))` in the test
- Assert `state.isDropTargeted == true` immediately after `acceptDrop` returns `true`
- Simulate session end with `.copy` operation and assert highlight persists
- Simulate session end with `.move` operation and assert highlight is cleared
- Use `TestStore.receive` matching for the final state assertion

**Source:** findings `FIND-001`; `EntryGridDropHighlightLifecycleTests.swift` (upstream reference)
```

The document ends with an optional footer note when prior compound artifacts exist for the same `plan_slug`:

```markdown
## Overlap/Deduplication Note

This learning document was generated from findings that were deduplicated against prior compound artifacts using the `dedupe_key` field. Prior compound artifacts for the same `plan_slug` are stored at:

- `.sisyphus/reviews/{plan_slug}/2026-04-09-120000/learning.md`

Merge by `category` when consulting multiple runs. Note which `run_id` each guidance entry came from.
```

````

---

## Fields for Machine Parsing

The compound learning document is primarily human-facing Markdown, but for machine parsing (Task 5 integration), the following frontmatter fields are recognized:

```markdown
---
run_id: "2026-04-10-181500"
plan_slug: "grid-drop-folder-thumbnail-ux-naturalization"
generated_at: "2026-04-10T18:15:00Z"
schema_version: "1.1"
total_entries: 4
---
```

These fields are optional but recommended for programmatic access.

---

## Schema Version History

| Version | Date       | Change          |
| ------- | ---------- | --------------- |
| 1.0     | 2026-04-10 | Initial schema. |
| 1.1     | 2026-05-17 | Added loop-retrospective fields: Plan Feedback, Catch Earlier, Reusability, Promotion, Confidence, Blast Radius. |
````
