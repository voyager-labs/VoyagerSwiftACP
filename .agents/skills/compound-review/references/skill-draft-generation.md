# Skill / Harness Draft Generation Rules

**Version:** 1.0  
**Path:** `.agents/skills/compound-review/references/skill-draft-generation.md`  
**Depends on:** `skill-draft-schema.md`, `findings-schema.md`, `artifact-contract.md`  
**Consumed by:** Task 8 (fixture verification)

---

## Overview

This document defines the generation rules that transform normalized findings (from `findings.json`) and notepad decisions (from `.sisyphus/notepads/{plan_slug}/decisions.md`) into a skill/harness draft document (`skill-draft.md`).

The rules govern:

1. **Draft eligibility** — which findings justify a draft proposal
2. **Subtype assignment** — `new-skill` vs `rule`
3. **Target path selection** — where the proposed file should live
4. **Rationale synthesis** — how the justification is built from sources
5. **Scope bounding** — what the draft proposes and what it explicitly excludes
6. **Source-Artifact Linkage** — machine-readable finding-to-draft mapping
7. **Overlap/deduplication** — how prior draft artifacts are reconciled

Drafts are **proposals only**. They do NOT auto-modify `.agents/skills/` or `.agents/rules/`. The operator decides whether and how to adopt them.

---

## Draft Eligibility Rules

### Threshold (from `skill-draft-schema.md` §Draft Threshold)

A skill/harness draft is emitted when **at least one** finding meets **all** of:

1. `verdict` is not `APPROVE` (the finding represents a problem), **OR** the finding is `APPROVE` but has `action_class` of `test-coverage` or `design` that could benefit from a harness.
2. `severity` is `medium` or higher.

**OR** when the operator explicitly requests a draft regardless of threshold.

### Additional Qualification from Notepads

Notepad `decisions.md` entries can independently motivate a draft when they:

1. Describe a **repeated pattern** the author had to resolve manually (e.g., "had to add the same guard in 3 places")
2. Document a **structural decision** that should be enforced automatically (e.g., "single owner for highlight clearing")
3. Note a **coverage gap** that required ad-hoc verification

These notepad-driven drafts follow the same generation rules but cite the notepad entry as the primary source.

### Multiple Findings → Single Draft vs Multiple Drafts

| Condition                                                                         | Action                                                                                             |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Multiple findings share the same domain and would target the same skill/rule path | Merge into a **single draft** with multiple Source Findings                                        |
| Findings span different domains or target different paths                         | Emit **separate drafts** per domain                                                                |
| One finding could justify both a new skill AND a new rule                         | Emit two drafts with distinct `Proposed Target` paths; cross-reference in their Non-Goals sections |

---

## Subtype Assignment Rules

Every draft is tagged as either `new-skill` or `rule` via its `Proposed Target` line.

### New Skill (`new-skill`)

Assign when the source material suggests:

- A **new verification capability** is needed (e.g., checking highlight lifecycle)
- An **orchestration workflow** should exist (e.g., a review pass for a specific subsystem)
- The proposed artifact lives under `.agents/skills/{skill-name}/SKILL.md`
- It has its own entry point, phases, and bounded output

**Heuristic:** If the finding's `action_class` is `test-coverage` or `design` and the fix requires reading specific files and asserting patterns, a new skill is the right target.

### Rule (`rule`)

Assign when the source material suggests:

- An **enforcement constraint** should be checked automatically (e.g., "no `setDropTargetEntryId(nil)` in acceptDrop success branches")
- A **pattern prohibition or requirement** can be expressed as a static rule
- The proposed artifact lives under `.agents/rules/{rule-name}.rule` or `.agents/rules/{group}/{rule-name}.md`
- It is consumed by existing skills (e.g., `voyager-dev`, `code-review`) as a constraint

**Heuristic:** If the finding's `action_class` is `code-quality` or `guardrail` and the fix is a pattern to enforce across files, a rule is the right target.

### Subtype Declaration Format

The draft header must declare the subtype:

```markdown
**Proposed Target:** `.agents/skills/{skill-name}/` (new skill, not yet created)
```

or

```markdown
**Proposed Target:** `.agents/rules/{rule-name}.rule` (new rule, not yet created)
```

---

## Target Path Selection Rules

### Skill Path

Format: `.agents/skills/{skill-name}/SKILL.md`

`{skill-name}` is derived from:

1. The finding's `category` field, hyphenated, with `-harness` or `-verification` suffix
2. If the category is too broad (e.g., `drag-drop-lifecycle`), narrow to the specific concern (e.g., `grid-drop-lifecycle`)
3. Check for name collision with existing skills under `.agents/skills/`; if a similar skill exists, the draft should propose **extending** it rather than creating a new one

### Rule Path

Format: `.agents/rules/{group}/{rule-name}.md` or `.agents/rules/{rule-name}.md`

`{group}` is derived from the repo's existing rule directory structure. If the rule applies to a specific subsystem (e.g., drag/drop coordinators), use the relevant group directory. If no group fits, place at the top level.

### Collision Handling

If the proposed target path already exists:

1. The draft must note this explicitly: `Proposed Target: .agents/skills/existing-skill/SKILL.md (extend existing skill)`
2. The `Proposed Scope` must describe what to **add** to the existing skill, not replace it
3. The `Non-Goals` must state: "Does not replace or restructure the existing skill — only adds the proposed scope"

---

## Rationale Synthesis Rules

The `Rationale` section is a 1–3 paragraph explanation grounded in specific findings.

### Synthesis Process

1. **Identify the core problem** from qualifying findings: what went wrong, what pattern was violated, what gap exists.
2. **Connect to notepad decisions** when available: why was a manual fix needed? What structural decision was made that should be automated?
3. **State the benefit** of the proposed skill/rule: what future regressions it prevents, what verification it enables.

### Rationale Quality Criteria

- References specific finding IDs (not just "a finding")
- Names specific files or patterns (not just "the codebase")
- States the **repetition risk** — why this will happen again without the proposed change
- Does not exceed 3 paragraphs

Bad: "Code quality could be improved with a new skill."
Good: "Finding `FIND-001` (severity high) identifies dual ownership of drop highlight clearing in `EntryGridCoordinator+Extensions.swift`. The fix (deferred clearing via `shouldClearAfterSessionEnd`) required manual verification across 5 call sites (decisions.md, 2026-04-09). Without automated enforcement, future drag/drop changes risk reintroducing the premature-clearing pattern."

---

## Scope Bounding Rules

### Proposed Scope

Each bullet in `Proposed Scope` must:

1. State a concrete action (read, verify, enforce, assert)
2. Name specific files or glob patterns
3. Be verifiable — the operator can confirm the scope is bounded

### Does NOT

Explicit out-of-scope items. Required when the draft subtype is `new-skill`. Must include at minimum:

- What existing skills handle (to avoid overlap)
- That it does not mutate product code
- That it does not create commits or PRs

### Non-Goals

Broader exclusions. Must include at minimum:

- No automatic Work loops
- No cross-repo artifact resolution (v1 constraint)

### Scope vs Non-Goal Distinction

- `Does NOT`: things the proposed skill/rule itself will not do
- `Non-Goals`: things other systems handle, or things explicitly excluded from this proposal's scope

---

## Source-Artifact Linkage Rules

The `Source-Artifact Linkage` table is the machine-readable core. It must:

1. Include **every** qualifying finding that contributed to the draft
2. Use exact finding IDs, dedupe_keys, and severity values from `findings.json`
3. Provide a short issue description for each row

### Linkage Table Format

| Column           | Source                                         | Required |
| ---------------- | ---------------------------------------------- | -------- |
| `Source Finding` | `findings[].id`                                | yes      |
| `Dedup Key`      | `findings[].dedupe_key`                        | yes      |
| `Severity`       | `findings[].severity`                          | yes      |
| `Issue`          | 1-line summary derived from `findings[].title` | yes      |

### Linkage Completeness

Every finding listed in `Source Findings` (the bulleted section) must appear in the linkage table. The linkage table must not contain findings not listed in `Source Findings`. These two sections are a bi-directional cross-reference.

---

## Overlap and Deduplication Against Prior Artifacts

### Prior Draft Detection

Before writing a skill-draft document, check for prior drafts for the same `plan_slug`:

1. Scan `.sisyphus/drafts/{plan_slug}/` for existing `skill-draft.md` files (different `run_id` directories).
2. If prior drafts exist, read their proposed targets and source findings.

### Overlap Handling

| Overlap Type                                     | Action                                                                                                                                 |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| Same proposed target path, same dedupe_keys      | **Update proposal**: new draft notes that prior draft exists, lists additional findings from this run. Prior draft is NOT overwritten. |
| Same proposed target path, different dedupe_keys | **Extend proposal**: new draft adds the new findings to the linkage table. Note which `run_id` each finding came from.                 |
| Different target paths, same dedupe_keys         | **Cross-reference**: both drafts exist; each notes the other in Non-Goals.                                                             |
| Contradictory scope                              | **Flag in Overlap Note**: prior draft's scope is preserved. New draft notes the contradiction. Operator resolves.                      |

### Overlap/Deduplication Note

The document must include an `## Overlap/Deduplication Note` section when prior drafts exist. Format:

```markdown
## Overlap/Deduplication Note

This skill-draft was generated against prior draft artifacts for the same `plan_slug`:

- `.sisyphus/drafts/{plan_slug}/{prior-run_id}/skill-draft.md`

Prior proposals are preserved. This draft may extend or contradict them; contradictions are flagged inline. Merge by consulting both linkage tables and resolving contradictions manually.
```

When **no** prior drafts exist, include a minimal statement:

```markdown
## Overlap/Deduplication Note

No prior skill-draft artifacts exist for this `plan_slug`. This is the first draft.
```

This ensures downstream consumers can distinguish "no overlap check needed" from "overlap check was performed and passed."

---

## Generation Sequence

The skill follows this sequence to produce the skill-draft document:

1. **Read findings** from `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json`
2. **Filter** findings by eligibility threshold (see Draft Eligibility Rules)
3. **Read notepad decisions** from `.sisyphus/notepads/{plan_slug}/decisions.md` for additional draft motivators
4. **Group** qualifying findings by domain — findings sharing a domain become a single draft
5. **Check for collision** with existing skills/rules at proposed target paths
6. **Assign subtypes** (`new-skill` or `rule`) based on finding characteristics
7. **Select target paths** using naming rules and collision checks
8. **Synthesize rationale** from finding descriptions and notepad context
9. **Bound scope** with concrete read/verify/enforce actions and explicit exclusions
10. **Build linkage table** from all qualifying findings
11. **Check prior drafts** in `.sisyphus/drafts/{plan_slug}/`
12. **Apply overlap/deduplication** against prior draft artifacts
13. **Write** to `.sisyphus/drafts/{plan_slug}/{run_id}/skill-draft.md`

### Empty Output

If no findings meet the draft threshold and no notepad decisions motivate a draft, the skill-draft document is still created but contains:

```markdown
# Skill / Harness Draft — {plan_slug}

**Run:** {run_id}  
**Generated:** {generated_at}  
**Proposed Target:** (none — no qualifying findings)

---

No findings met the draft threshold for this run. No skill or rule proposals generated.
```

---

## Readiness States

The `Readiness` field must be one of:

| State                                                | Meaning                                                            |
| ---------------------------------------------------- | ------------------------------------------------------------------ |
| `Draft only. Requires human review before adoption.` | Default for all generated drafts.                                  |
| `Needs human review`                                 | Same as above, explicit.                                           |
| `Ready for adoption`                                 | Only after operator has reviewed and approved. Not auto-set.       |
| `Adopted`                                            | Only after the proposed skill/rule has been created. Not auto-set. |

All v1 generated drafts start at `Draft only. Requires human review before adoption.` The operator advances the readiness state through manual review.

---

## Schema Compliance

The generated document must conform to `skill-draft-schema.md` (Version 1.0). Specifically:

- Document header matches the template in `skill-draft-schema.md` §Document Structure
- All required fields are present: Proposal (H2), Rationale, Source Findings, Proposed Scope, Target File, Non-Goals, Readiness, Source-Artifact Linkage
- Optional `Does NOT` field is present for `new-skill` drafts
- Linkage table matches the four-column format exactly
- Subtype is declared in the `Proposed Target` header line

---

## Version History

| Version | Date       | Change         |
| ------- | ---------- | -------------- |
| 1.0     | 2026-04-10 | Initial rules. |
