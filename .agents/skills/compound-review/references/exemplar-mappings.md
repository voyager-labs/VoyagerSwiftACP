# Exemplar Mappings — Governance Classification Reference

**Version:** 1.0
**Purpose:** Seeds the promotion governance model with explicit exemplar cases showing how `promotion-policy.md` classifies adopted, promotable, blocked, and local-only evidence. Each exemplar demonstrates the full classification pipeline: source artifacts → trust classification → promotion eligibility → resulting governance state.
**Consumed by:** `promotion-policy.md` §9 worked examples, compound-review Phase 4 promotion-eligibility annotations, and Stage 3 adoption decisions.

---

## Classification States

Every compound-review output maps to exactly one of these governance states:

| State          | Meaning                                                  | Governance action                                |
| -------------- | -------------------------------------------------------- | ------------------------------------------------ |
| **Adopted**    | Artifact promoted and committed to `.agents/`.           | Enforced as project governance.                  |
| **Local-only** | Artifact remains in `.sisyphus/` — not promoted.         | Available as context, not enforced.              |
| **Blocked**    | Artifact cannot promote due to trust or lineage failure. | Must re-run or investigate before any promotion. |

---

## Exemplar 1: Adopted — Scope-Diff Isolation

### Source artifacts

| Artifact                                                                          | Role                   |
| --------------------------------------------------------------------------------- | ---------------------- |
| `.sisyphus/compound/voy-225-window-shell-split/2026-04-16-133347/learning.md`     | Learning entry (run 1) |
| `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-052652/learning.md` | Learning entry (run 2) |
| `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-133347/learning.md` | Learning entry (run 3) |
| `.sisyphus/drafts/voy-225-window-shell-split/2026-04-16-133347/skill-draft.md`    | Draft proposal         |

### Learning entry identity

- **Category:** `scope-fidelity`
- **Tags:** `[scope-fidelity, worktree-isolation, multi-issue-chain, evidence-quality]`
- **Type:** `bug-resolution`
- **Applies when:** Multi-issue worktree branches where per-issue scope verification relies on accumulated working-tree diffs.

### Trust classification: `authoritative` (anchored by voy-226 runs; voy-225 contributes as `reference-only`)

Two source runs are authoritative, one is reference-only:

1. **VOY-225, run 2026-04-16-133347** — complete run with findings, learning, and draft. No `FAILURE.md`. **Trust class: `reference-only`** (all four facets missing, `confidence_reduced: true`). When paired with authoritative voy-226 runs, the combined evidence supports promotion per taxonomy §7.
2. **VOY-226, run 2026-04-16-052652** — earlier authoritative run for voy-226. Contains the same scope-fidelity category with identical tags.
3. **VOY-226, run 2026-04-16-133347** — later authoritative run for voy-226. Deduplication note in learning.md confirms overlap with run 052652.

**Note:** VOY-225 run 2026-04-16-133347 is individually `reference-only` (all four facets missing, `confidence_reduced: true`). However, per evidence-trust-taxonomy.md §7 decision tree, reference-only runs may contribute to promotion when paired with authoritative runs. The two authoritative voy-226 runs provide the authoritative anchor; voy-225 enriches the evidence base as corroborating reference.

### Promotion eligibility: **Eligible → CREATE NEW**

**Recurrence check:**

| Run                            | plan_slug                      | Dedupe/tag match | Independent?           |
| ------------------------------ | ------------------------------ | ---------------- | ---------------------- |
| voy-225, run 2026-04-16-133347 | voy-225-window-shell-split     | Tags match       | Yes                    |
| voy-226, run 2026-04-16-052652 | voy-226-top-orchestrator-split | Tags match       | Yes                    |
| voy-226, run 2026-04-16-133347 | voy-226-top-orchestrator-split | Tags match       | Yes (different run_id) |

- Independent runs: **3**
- Cross-plan recurrence: **YES** (voy-225 and voy-226 are different plan_slugs)
- Threshold ≥2: **PASS**

**Confidence score:**

| Signal                                         | Points |
| ---------------------------------------------- | ------ |
| 2 independent authoritative runs × +2          | +4     |
| 1 reference-only run paired with authoritative | +1     |
| Cross-plan recurrence bonus                    | +1     |
| Learning entries present (3 runs)              | +1     |
| **Total**                                      | **7**  |

Threshold ≥5: **PASS**

**Conflict check:**

- No existing `.agents/` artifact addressed scope-diff isolation at time of adoption.
- No dedupe_key match, no category/tag overlap with existing rules.
- **No conflict → CREATE NEW**

### Resulting governance state: **Adopted**

- **Adopted artifact:** `.agents/rules/00-core/05-scope-diff-isolation.md`
- **Placement rationale:** `00-core/` because scope-diff isolation applies across all domains, not just macOS or backend.
- **Status:** Committed to `.agents/`. Enforced as project governance.
- **Source evidence pointer:** `Source: .sisyphus/compound/voy-225-window-shell-split/2026-04-16-133347/learning.md`, `Source: .sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-052652/learning.md`

---

## Exemplar 2: Adopted — Xcode Test-Plan Visibility

### Source artifacts

| Artifact                                                                           | Role                   |
| ---------------------------------------------------------------------------------- | ---------------------- |
| `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-052652/learning.md`  | Learning entry (run 1) |
| `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-133347/learning.md`  | Learning entry (run 2) |
| `.sisyphus/drafts/voy-226-top-orchestrator-split/2026-04-16-133347/skill-draft.md` | Draft proposal         |

### Learning entry identity

- **Category:** `test-execution-limitation`
- **Tags:** `[test-execution, xcode-cli, spm-package-tests, test-plan-configuration, voyager-pattern]`
- **Type:** `harness-guidance`
- **Applies when:** Running `xcodebuild test` with `shouldAutocreateTestPlan=YES` where the scheme references SPM package test targets.

### Trust classification: `authoritative`

Both source runs are authoritative:

1. **VOY-226, run 2026-04-16-052652** — earlier authoritative run. Contains the test-execution-limitation category with identical tags and detailed guidance.
2. **VOY-226, run 2026-04-16-133347** — later authoritative run. Same category/tags. Deduplication note confirms overlap.

Note: Although the earlier run (052652) is technically superseded by the later run (133347) and would be classified `reference-only` in isolation, the finding is corroborated by the authoritative later run. The combined evidence is authoritative.

### Promotion eligibility: **Eligible → CREATE NEW**

**Recurrence check:**

| Run                            | plan_slug                      | Dedupe/tag match | Independent?           |
| ------------------------------ | ------------------------------ | ---------------- | ---------------------- |
| voy-226, run 2026-04-16-052652 | voy-226-top-orchestrator-split | Tags match       | Yes                    |
| voy-226, run 2026-04-16-133347 | voy-226-top-orchestrator-split | Tags match       | Yes (different run_id) |

- Independent runs: **2** (same plan, different run_ids — counts per §3.2)
- Cross-plan recurrence: **NO** (both voy-226)
- Threshold ≥2: **PASS**

**Confidence score:**

| Signal                                | Points |
| ------------------------------------- | ------ |
| 2 independent authoritative runs × +2 | +4     |
| Learning entries present (2 runs)     | +1     |
| Multiple facets confirmed within runs | +1     |
| **Total**                             | **6**  |

Threshold ≥5: **PASS**

**Conflict check:**

- No existing `.agents/` artifact addressed SPM test-plan visibility.
- Tags partially overlap with scope-diff rule (`evidence-quality`) but domain is distinct.
- **No conflict → CREATE NEW**

### Resulting governance state: **Adopted**

- **Adopted artifact:** `.agents/rules/30-macos/04-xcode-test-plan-visibility.md`
- **Placement rationale:** `30-macos/` because this is an Xcode/SPM-specific behavior scoped to macOS development. The rule's Must not section explicitly forbids generalizing to `00-core`.
- **Status:** Committed to `.agents/`. Enforced as project governance.
- **Source evidence pointer:** `Source: .sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-052652/learning.md`

---

## Exemplar 3: Blocked — Stale-Lineage Failure (voy-223)

### Source artifacts

| Artifact                                                                            | Role           |
| ----------------------------------------------------------------------------------- | -------------- |
| `.sisyphus/reviews/voy-223-filemanager-packageization/2026-04-16-133347/FAILURE.md` | Failure report |

### Failure details

- **Run:** 2026-04-16-133347
- **Failure mode:** report-and-stop
- **Failed precondition:** P5 (stale lineage)
- **Root cause:** Plan was modified after the latest associated evidence timestamp. Plan mtime `2026-04-13T19:12:39Z` > latest evidence mtime `2026-04-13T19:02:18Z`.

### Trust classification: `invalid`

Per `evidence-trust-taxonomy.md`:

- The run produced only a `FAILURE.md` — no manifest, findings, learning, or draft.
- Stale lineage is non-recoverable (notepad `decisions.md`: "A stale run is permanently invalid. No re-reading or patching.").
- The FAILURE.md itself is valid as a historical record but the run's outputs cannot serve as governance evidence.

### Promotion eligibility: **Blocked**

| Blocking condition                            | Rationale                                                                                  |
| --------------------------------------------- | ------------------------------------------------------------------------------------------ |
| No findings, learning, or draft produced      | Cannot evaluate promotion for artifacts that do not exist.                                 |
| Stale lineage (P5 failure)                    | Per `workflow-boundaries.md`, stale-lineage runs must stop without emitting any artifacts. |
| Source run produced no authoritative evidence | The only output is `FAILURE.md`. No findings.json, no learning.md, no skill-draft.md.      |

**No promotion confidence score can be computed.** The run emitted no scored outputs.

### Resulting governance state: **Blocked — stays local-only in `.sisyphus/`**

- **Artifact location:** `.sisyphus/reviews/voy-223-filemanager-packageization/2026-04-16-133347/FAILURE.md`
- **Governance action:** None. The FAILURE.md is preserved as historical context but carries no governance weight.
- **Recovery path:** The operator must trigger a new compound-review run for voy-223 with fresh evidence. The stale run cannot be salvaged.
- **Lesson:** Stale-lineage failures demonstrate why baseline capture (per `05-scope-diff-isolation.md`) matters for governance integrity. Without verifiable evidence lineage, no governance decision can be made.

---

## Exemplar 4: Local-Only — Single-Run Ownership Patterns

### Source artifacts

| Artifact                                                                           | Role                                                |
| ---------------------------------------------------------------------------------- | --------------------------------------------------- |
| `.sisyphus/compound/voy-225-window-shell-split/2026-04-16-133347/learning.md`      | Learning (window-shell decomposition, test-pattern) |
| `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-133347/learning.md`  | Learning (reducer-pattern)                          |
| `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-052652/learning.md`  | Learning (reducer-pattern, earlier run)             |
| `.sisyphus/drafts/voy-225-window-shell-split/2026-04-16-133347/skill-draft.md`     | Draft (scope-diff only)                             |
| `.sisyphus/drafts/voy-226-top-orchestrator-split/2026-04-16-133347/skill-draft.md` | Draft (test-plan only)                              |

### Learning entries under consideration

Three learning entries do NOT map to already-adopted rules:

1. **`window-shell-decomposition`** (voy-225 learning, category: `window-shell-decomposition`)
    - Tags: `[window-shell, coordinator-pattern, shared-utility, backward-compatibility]`
    - Appears in: voy-225 run 2026-04-16-133347 only
    - Recurrence count: **1**

2. **`reducer-pattern: thin composition root`** (voy-226 learning, category: `reducer-pattern`)
    - Tags: `[reducer-pattern, tca-composition-root, command-routing, ownership-extraction, voyager-pattern]`
    - Appears in: voy-226 run 2026-04-16-052652 and voy-226 run 2026-04-16-133347
    - Recurrence count: **2** (but same plan_slug, no cross-plan recurrence)

3. **`test-pattern: expected-failure markers`** (voy-225 learning, category: `test-pattern`)
    - Tags: `[test-pattern, xctexpectfailure, migration-ledger, package-tests]`
    - Appears in: voy-225 run 2026-04-16-133347 only
    - Recurrence count: **1**

### Trust classification: `authoritative` (all source runs)

The learning entries themselves come from authoritative runs. The question is not trust but recurrence sufficiency.

### Promotion eligibility analysis

#### Entry 1: window-shell-decomposition

| Criterion          | Value                                     | Pass?     |
| ------------------ | ----------------------------------------- | --------- |
| Recurrence         | 1 (voy-225 only)                          | FAIL      |
| Cross-plan         | N/A (single run)                          | N/A       |
| Promotion score    | +2 (1 auth run) + 0 + 1 (learning) = 3    | FAIL (<5) |
| Blocking condition | Single-run anecdote, no operator override | BLOCK     |

**Result:** STAY LOCAL-ONLY

#### Entry 2: reducer-pattern (thin composition root)

| Criterion       | Value                                                            | Pass?       |
| --------------- | ---------------------------------------------------------------- | ----------- |
| Recurrence      | 2 (voy-226 runs 052652 and 133347)                               | PASS (≥2)   |
| Cross-plan      | NO (both voy-226)                                                | No bonus    |
| Promotion score | +4 (2 auth runs) + 0 + 1 (learning) = 5                          | PASS (≥5)   |
| Draft exists?   | No dedicated draft for reducer-pattern                           | No +1       |
| Conflict check  | No existing `.agents/` artifact for TCA composition-root pattern | No conflict |

This entry meets the numerical threshold. However:

- Both runs are same `plan_slug` (voy-226). The recurrence is same-plan, not cross-plan.
- The pattern is specific to TCA reducer decomposition within the Voyager macOS app.
- No dedicated skill-draft proposes a specific target file.
- The guidance is useful but highly context-specific.

**Classification:** The entry is **promotion-eligible** by the numbers but should be treated as **local-only pending broader recurrence**. If a future plan (e.g., voy-227 or later) independently produces the same reducer-pattern finding with cross-plan recurrence, promotion becomes strongly warranted.

**Current result:** STAY LOCAL-ONLY (operator discretion for immediate promotion)

#### Entry 3: test-pattern (expected-failure markers)

| Criterion          | Value                                     | Pass?     |
| ------------------ | ----------------------------------------- | --------- |
| Recurrence         | 1 (voy-225 only)                          | FAIL      |
| Cross-plan         | N/A (single run)                          | N/A       |
| Promotion score    | +2 (1 auth run) + 0 + 1 (learning) = 3    | FAIL (<5) |
| Blocking condition | Single-run anecdote, no operator override | BLOCK     |

**Result:** STAY LOCAL-ONLY

### Resulting governance state: **Local-only — stays in `.sisyphus/`**

- **Artifact locations:**
    - `.sisyphus/compound/voy-225-window-shell-split/2026-04-16-133347/learning.md`
    - `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-133347/learning.md`
    - `.sisyphus/compound/voy-226-top-orchestrator-split/2026-04-16-052652/learning.md`
    - `.sisyphus/drafts/voy-225-window-shell-split/2026-04-16-133347/skill-draft.md`
    - `.sisyphus/drafts/voy-226-top-orchestrator-split/2026-04-16-133347/skill-draft.md`
- **Governance action:** None. These artifacts remain available as contextual reference in `.sisyphus/` but are not promoted to `.agents/`.
- **Rationale:** Insufficient cross-plan recurrence (entries 1, 3) or context-specific pattern that should await broader confirmation (entry 2).
- **Not a governance failure:** Local-only is the correct classification for single-run or narrow-scope patterns. Premature promotion would create brittle rules.

---

## Classification Matrix Summary

| Exemplar                                | Trust class      | Recurrence | Score | Promotion state  | Governance location                                       |
| --------------------------------------- | ---------------- | ---------- | ----- | ---------------- | --------------------------------------------------------- |
| Scope-Diff Isolation                    | auth(2) + ref(1) | 3          | 7     | **Adopted**      | `.agents/rules/00-core/05-scope-diff-isolation.md`        |
| Xcode Test-Plan Visibility              | authoritative    | 2          | 6     | **Adopted**      | `.agents/rules/30-macos/04-xcode-test-plan-visibility.md` |
| Stale-Lineage Failure (voy-223)         | invalid          | N/A        | N/A   | **Blocked**      | `.sisyphus/reviews/voy-223-*/FAILURE.md`                  |
| Window-Shell Decomposition              | authoritative    | 1          | 3     | **Local-only**   | `.sisyphus/compound/voy-225-*/learning.md`                |
| Reducer-Pattern (Composition Root)      | authoritative    | 2          | 5     | **Local-only\*** | `.sisyphus/compound/voy-226-*/learning.md`                |
| Test-Pattern (Expected-Failure Markers) | authoritative    | 1          | 3     | **Local-only**   | `.sisyphus/compound/voy-225-*/learning.md`                |

\* Reducer-pattern meets threshold but is same-plan only. Operator discretion applies.

---

## Bootstrap Note: Pre-Governance Adoptions

The two adopted exemplars (Scope-Diff Isolation, Xcode Test-Plan Visibility) were promoted to `.agents/` **before** the governance system defined in this document set existed. Their source manifests have `confidence_reduced: true` with all four facets missing because the facet model did not exist at the time of their compound-review runs.

**Implications:**

1. These adoptions are **pre-governance** and do not need to satisfy the current promotion thresholds retroactively.
2. The exemplar entries above describe the **intended governance pipeline behavior** — they model how similar findings _should_ be classified and promoted under the new system when authoritative runs with complete facets become available.
3. Going forward, all new promotions must satisfy the full lifecycle contract: authoritative trust class, ≥2 recurrence, confidence score ≥5 (CREATE) or ≥3 (EXTEND), and human-reviewed adoption via `04-adoption-and-rollback.md`.

**In other words:** the exemplars demonstrate the governance model's target state. The fact that their historical source data is `reference-only` reflects the bootstrapping transition, not a policy failure.

---

## How to Use These Exemplars

1. **When classifying new findings:** Compare the new finding's recurrence count, trust class, and confidence score against the matrix above. Find the closest matching exemplar. Apply the same governance state.

2. **When evaluating promotion:** Use the Adopted exemplars as proof that the promotion pipeline works end-to-end. Use the Blocked exemplar as proof that stale evidence is correctly rejected. Use the Local-only exemplars as proof that single-run patterns are preserved without premature promotion.

3. **When auditing governance history:** Each exemplar's source artifacts are traceable through the source evidence pointers. Any adopted rule can be traced back to the specific learning entries and runs that produced it.

---

## Schema Version History

| Version | Date       | Change             |
| ------- | ---------- | ------------------ |
| 1.0     | 2026-04-17 | Initial bootstrap. |
