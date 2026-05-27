# Compound Learning Generation Rules

**Version:** 1.0  
**Path:** `.agents/skills/compound-review/references/compound-learning-generation.md`  
**Depends on:** `learning-schema.md`, `findings-schema.md`, `artifact-contract.md`  
**Consumed by:** Task 8 (fixture verification)

---

## Overview

This document defines the generation rules that transform normalized findings (from `findings.json`) and notepad learnings (from `.sisyphus/notepads/{plan_slug}/learnings.md` and `decisions.md`) into a compound learning document (`learning.md`).

The rules govern:

1. **Source selection** — which findings and notepad entries qualify
2. **Type assignment** — `bug-resolution` vs `harness-guidance`
3. **Category grouping** — how entries are organized under H2 headings
4. **Applicability extraction** — how `Applies when` conditions are derived
5. **Guidance synthesis** — how actionable rules are produced from sources
6. **Lineage grounding** — every output traces to exact source artifacts
7. **Overlap/deduplication** — how prior compound artifacts are reconciled

---

## Source Selection Rules

### Finding Qualification

Not every finding becomes a compound learning entry. A finding qualifies when it meets **any** of:

| Qualification Criterion                                      | Rationale                                                                                                            |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `action_class` is `test-coverage` or `design`                | These encode patterns that future agents can reuse.                                                                  |
| `verdict` is `REJECT` or `CONDITIONAL`                       | These represent problems that required resolution — the resolution pattern is the learning.                          |
| `severity` is `high` or `critical`                           | High-severity findings almost always carry reusable operational knowledge about what went wrong and how to avoid it. |
| `action_class` is `code-quality` AND `severity` is `medium`+ | Code quality patterns at medium+ severity often generalize.                                                          |
| `action_class` is `scope`                                    | Scope fidelity lessons are broadly reusable across planning cycles.                                                  |

Findings that are `APPROVE` + `low`/`informational` + `code-quality` or `guardrail` generally **do not** qualify unless they carry an unusually clear reusable pattern.

### Notepad Entry Qualification

Notepad entries are a secondary source. They qualify when they:

1. Appear under `##` date-stamped sections in `learnings.md` or `decisions.md`
2. Describe a **root cause** + **fix** or a **decision** + **rationale** pair
3. Contain specific code paths, file names, or test strategies (not just diary notes)

Notepad entries that are purely chronological ("Session started", "moved to file X") do **not** qualify.

### Finding vs Notepad Priority

When a finding and a notepad entry describe the same issue (matched by `dedupe_key` or semantic overlap):

- The finding is the **primary source** for the learning entry
- The notepad entry supplements `Guidance` with operational context (e.g., _why_ a fix was chosen over alternatives)
- The `Source` field lists both, with the finding ID first

---

## Type Assignment Rules

Every learning entry gets a `Type` tag: `bug-resolution` or `harness-guidance`.

### Bug Resolution (`bug-resolution`)

Assign when the source material describes:

- A defect that was identified and resolved
- A root cause analysis with a specific fix
- An incorrect behavior corrected in product code or tests

The `Guidance` section encodes the **correct behavior** and what to **avoid** (the buggy pattern).

### Harness Guidance (`harness-guidance`)

Assign when the source material describes:

- A test strategy or verification pattern
- A harness setup or test structure that worked well
- A coverage gap and how it was closed
- A coordinator/mock/stub pattern for testing

The `Guidance` section encodes **how to write the test** and **what to assert**.

### Mixed Cases

When a single finding covers both a bug fix and a test pattern:

- Emit **two** learning entries under the same category
- One tagged `bug-resolution` (the fix), one tagged `harness-guidance` (the test)
- Both reference the same source finding ID
- Cross-reference each other in their `Source` fields

---

## Category Grouping Rules

Categories group related learning entries under `## Category: {slug}` headings.

### Category Assignment

1. **From findings:** Use the finding's `category` field as the initial category slug.
2. **From notepads:** Extract a category from the notepad section header or the domain of the decision (e.g., decisions about `EntryGridCoordinator` → `coordinator-state-ownership`).
3. **Merge semantically:** If two categories differ in slug but cover the same domain (e.g., `drag-drop-lifecycle` and `drop-highlight`), merge under the broader category.

### Category Ordering Within Document

Order categories by **finding severity** — the category containing the highest-severity qualifying finding comes first. Within a category, order entries by severity descending.

### Minimum Category Coverage

A category must contain at least one learning entry. If category assignment produces an empty category (all entries were re-categorized), omit the empty heading.

---

## Applicability Extraction Rules

The `Applies when` field lists concrete conditions under which the guidance is relevant. It is derived from:

1. **Finding context:** The `category` and `description` fields of the source finding identify the domain (e.g., "grid drag/drop", "coordinator state").
2. **Notepad decisions:** The "Why" section of a decision entry identifies the conditions that motivated the decision.
3. **Code paths mentioned:** File names, function names, or class names in the source material narrow the applicability scope.

### Applicability Quality Criteria

Each `Applies when` bullet must be:

- **Specific enough** to exclude unrelated contexts (not "when using Swift")
- **General enough** to apply beyond the current run (not "in file X on line Y")
- **Factual** — derived from source material, not inferred

Bad: "When working on Voyager"
Good: "Grid drag/drop session where `.copy` is the detected operation in a coordinator-based AppKit drag/drop with TCA state"

---

## Guidance Synthesis Rules

The `Guidance` field lists actionable rules. Each bullet is a concrete do/don't directive.

### Synthesis Process

1. **Extract the fix or pattern** from the finding's `description` and the notepad's decision rationale.
2. **Generalize** from the specific to the pattern. Replace specific variable names with generic roles (e.g., "the coordinator" instead of "EntryGridCoordinator") unless the specificity is load-bearing.
3. **State positively** for do-rules, **state as prohibition** for don't-rules.
4. **Limit to 4–7 bullets** per learning entry. If more rules emerge, split into two entries.

### Guidance Quality Criteria

- Each bullet is **self-contained** — it can be understood without reading the finding
- Each bullet is **actionable** — it tells the reader exactly what to do or avoid
- No bullet is a tautology ("use best practices")
- Specific code patterns are preserved when they are the point (e.g., `shouldClearAfterSessionEnd(operation:)`)

---

## Lineage Grounding Rules

Every learning entry's `Source` field must include:

1. **Finding IDs** — e.g., `FIND-001`, `FIND-003`
2. **Notepad references** — e.g., `decisions.md` (2026-04-09 session-local validated destination)
3. **Facet references** — e.g., `f1 plan compliance audit`

### Source Format

```
**Source:** findings `FIND-001`, `FIND-003`; notepad `decisions.md` (2026-04-09 entry); f2 code quality review
```

The format is: finding IDs first, then notepad references with dates, then facet names. This enables downstream consumers to trace back to the exact source artifacts without parsing freeform prose.

---

## Overlap and Deduplication Against Prior Artifacts

### Prior Artifact Detection

Before writing a compound learning document, the generation rules require checking for prior compound outputs for the same `plan_slug`:

1. Scan `.sisyphus/reviews/{plan_slug}/` for existing `learning.md` files (different `run_id` directories).
2. If prior artifacts exist, read their category structure and guidance entries.

### Overlap Handling

When the current run's findings overlap with prior compound learning:

| Overlap Type                             | Action                                                                                                                  |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Same `category` + same `dedupe_key`      | Merge: keep both entries, note which `run_id` each came from. Prior entry is preserved verbatim; new entry is appended. |
| Same `category` + different `dedupe_key` | No conflict: append new entry under the same category heading.                                                          |
| Different `category` + same `dedupe_key` | Cross-reference: both entries exist under their respective categories, each noting the other's location.                |
| Contradictory guidance                   | Flag in `Overlap/Deduplication Note` section. Prior guidance is NOT overwritten. The operator resolves.                 |

### Overlap/Deduplication Note

The document footer must include an `## Overlap/Deduplication Note` section when prior artifacts exist. Format:

```markdown
## Overlap/Deduplication Note

This learning document was generated from findings that were deduplicated against prior compound artifacts using the `dedupe_key` field. Prior compound artifacts for the same `plan_slug` are stored at:

- `.sisyphus/reviews/{plan_slug}/{prior-run_id}/learning.md`

Merge by `category` when consulting multiple runs. Note which `run_id` each guidance entry came from. Contradictions (if any) are flagged inline.
```

When **no** prior artifacts exist, omit this section entirely.

---

## Generation Sequence

The skill follows this sequence to produce the compound learning document:

1. **Read findings** from `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json`
2. **Filter** findings by qualification criteria (see Source Selection Rules)
3. **Read notepads** from `.sisyphus/notepads/{plan_slug}/learnings.md` and `decisions.md`
4. **Filter** notepad entries by qualification criteria
5. **Match** findings to notepad entries by semantic overlap (dedupe_key, category, domain)
6. **Check prior artifacts** in `.sisyphus/reviews/{plan_slug}/`
7. **Assign types** (`bug-resolution` or `harness-guidance`)
8. **Group by category** and order by severity
9. **Extract applicability** from finding descriptions and notepad context
10. **Synthesize guidance** from fix patterns and decision rationale
11. **Ground lineage** in source finding IDs and notepad references
12. **Apply overlap/deduplication** against prior compound artifacts
13. **Write** to `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`

### Empty Output

If no findings qualify and no notepad entries qualify, the compound learning document is still created but contains:

```markdown
# Compound Learning — {plan_slug}

**Run:** {run_id}  
**Generated:** {generated_at}  
**Lineage:** {lineage.source_plan}

---

No qualifying findings or notepad entries for compound learning in this run.
```

This prevents downstream consumers from wondering whether the output was simply not generated.

---

## Schema Compliance

The generated document must conform to `learning-schema.md` (Version 1.0). Specifically:

- Document header matches the template in `learning-schema.md` §Document Structure
- Each entry has all 7 required fields: Category, learning-title, Type, Tags, Applies when, Guidance, Source
- `Type` is one of: `bug-resolution`, `harness-guidance`
- `Tags` is a non-empty array of lowercase hyphenated strings
- Optional YAML frontmatter (run_id, plan_slug, generated_at, schema_version, total_entries) is included when the document has qualifying entries

---

## Version History

| Version | Date       | Change         |
| ------- | ---------- | -------------- |
| 1.0     | 2026-04-10 | Initial rules. |
