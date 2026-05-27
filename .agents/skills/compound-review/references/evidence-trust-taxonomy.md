# Evidence Trust Taxonomy for Governance Promotion

**Version:** 1.0
**Scope:** Defines which `.sisyphus` artifacts are authoritative, reference-only, or invalid for compound-review governance promotion decisions.
**Source of truth for:** Downstream consumers of compound-review output. Task 2 (lifecycle contract), Task 4 (compound-review redesign), and Task 9 (governance cadence) must conform.
**Normative references:** `artifact-contract.md`, `workflow-boundaries.md`, `findings-schema.md`, `learning-schema.md`, `manifest-schema.md`

---

## 1. Purpose

Governance promotion, meaning the decision to trust a compound-review run's outputs enough to base downstream actions on them, requires a clear classification system. Not all artifacts carry equal weight. A successful learning.md from a validated run is different from a FAILURE.md that records why a run could not proceed.

This taxonomy provides:

1. Three trust classes (`authoritative`, `reference-only`, `invalid`) with explicit entry criteria.
2. Downstream actions for each class, so consuming agents and human operators know what they may do with a classified artifact.
3. Handling rules for stale lineage, malformed artifact-contract output, missing inputs, and duplicate findings across reruns.

---

## 2. Trust Classes

### 2.1 Class: `authoritative`

An `authoritative` artifact is a complete, validated output from a compound-review run that passed all required preconditions (P1 through P6 in `workflow-boundaries.md`). It may be used as the basis for governance promotion decisions, downstream skill proposals, and learning compounding.

**Entry criteria (all must hold):**

| Criterion                               | Description                                                                                                                                                                                                         |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1-P6 pass                              | The run passed every required precondition in `workflow-boundaries.md` §6.                                                                                                                                          |
| No FAILURE.md exists for this run       | The run directory `.sisyphus/reviews/{plan_slug}/{run_id}/` does NOT contain a `FAILURE.md`.                                                                                                                        |
| manifest.json exists and is well-formed | The manifest at `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json` parses as valid JSON with the required top-level fields (`schema_version`, `run_id`, `plan_slug`, `run_at`, `inputs`, `outputs`, `lineage`). |
| Stale check passes                      | No `inputs.*.path` file has a last-modified timestamp after the `run_at` timestamp in the manifest. See `artifact-contract.md` §Stale Detection Rule.                                                               |
| findings.json exists                    | The file at the manifest's `outputs.findings` path exists and is parseable.                                                                                                                                         |
| lineage is complete                     | The manifest's `lineage.source_plan` path resolves to an existing file, and `lineage.source_evidence` contains at least one entry.                                                                                  |

**Note:** The run MAY have `confidence_reduced: true` in the manifest (missing optional facets or notepads). Confidence reduction degrades the run's coverage but does not by itself disqualify it from `authoritative` status, **except when all four facets are missing** (see §5.2). The reduction is explicit, not silent.

**Downstream actions for `authoritative` artifacts:**

| Action                                                    | Permitted | Condition                                                        |
| --------------------------------------------------------- | --------- | ---------------------------------------------------------------- |
| Base governance promotion on findings                     | Yes       | Consider `confidence_reduced` flag when assessing weight.        |
| Extract learning entries for future runs                  | Yes       |                                                                  |
| Submit skill-draft proposals via `skill-creator`          | Yes       | Draft must meet threshold in `skill-draft-schema.md`.            |
| Treat findings as evidence of plan compliance             | Yes       | Weight by `facets_consumed` count. More facets = broader review. |
| Promote to cross-run deduplication baseline               | Yes       | Use `dedupe_key` fields for cross-run merge.                     |
| Re-run compound-review on same plan_slug with same run_id | No        | P4 prohibits conflicting runs.                                   |

**Eligible artifact paths:**

- `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json`
- `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json`
- `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`
- `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`

---

### 2.2 Class: `reference-only`

A `reference-only` artifact carries useful context but cannot serve as proof of governance compliance. It may be consulted for background, historical patterns, or cross-referencing, but it MUST NOT be used as the sole basis for promoting a plan through a governance gate.

**Entry criteria (any one triggers this class):**

| Criterion                            | Description                                                                                                                                                                                                                                                                    |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Confidence-reduced run               | The manifest has `confidence_reduced: true` AND two or more facets are missing (`facets_missing` has length >= 2). Single missing facet is still `authoritative` if all other criteria pass.                                                                                   |
| Prior-run overlap                    | The artifact is from an earlier run_id for the same `plan_slug`, and a newer run exists that is `authoritative`. The earlier run is demoted to `reference-only`.                                                                                                               |
| Notepad-only enrichment              | The artifact is a notepad file (learnings, decisions, issues, problems) that was consumed by a run but is not itself a review output. Notepads are `reference-only` inputs.                                                                                                    |
| Evidence file without review context | A `task-{N}-*.*` evidence file that exists but has not been through a compound-review run. Raw evidence is supporting material, not synthesized finding.                                                                                                                  |
| Partial manifest                     | The manifest exists but is missing one or more optional output paths (e.g., `learning.md` was not generated because no findings met the draft threshold). The manifest itself is `reference-only` for the missing outputs but `authoritative` for the outputs it does contain. |
| Cross-run deduplication source       | An older learning.md referenced in an Overlap/Deduplication Note. It provides context for the current run's deduplicated entries.                                                                                                                                              |

**Downstream actions for `reference-only` artifacts:**

| Action                                                 | Permitted | Condition                                                                             |
| ------------------------------------------------------ | --------- | ------------------------------------------------------------------------------------- |
| Consult for historical context                         | Yes       | Do not treat as current truth.                                                        |
| Cross-reference with authoritative findings            | Yes       | Use to enrich understanding, not to override.                                         |
| Base governance promotion on                           | No        | Must pair with at least one `authoritative` artifact for the same plan.               |
| Extract learning entries verbatim into new learning.md | Partially | Merge by `category`, attribute to original `run_id`. Do not copy without attribution. |
| Ignore entirely                                        | Yes       | Downstream consumer may choose to skip reference-only artifacts.                      |

**Eligible artifact paths:**

- Any path listed under `authoritative` that has been superseded by a newer `authoritative` run for the same `plan_slug`.
- `.sisyphus/notepads/{plan_slug}/*.md` (all notepad family files).
- `.sisyphus/evidence/{plan_slug}/task-{N}-*.*` (raw evidence files).
- `.sisyphus/evidence/{plan_slug}/f{1-4}-*.md` (raw facet files).

---

### 2.3 Class: `invalid`

An `invalid` artifact cannot be trusted for any governance purpose. It represents a failed, stale, malformed, or corrupted state. It MUST NOT be used for governance promotion, learning extraction, or baseline establishment.

**Entry criteria (any one triggers this class):**

| Criterion                                           | Description                                                                                                                                                                                                                                                   |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FAILURE.md exists for this run                      | The run directory contains `FAILURE.md`. The run stopped before producing outputs.                                                                                                                                                                            |
| Stale lineage detected                              | Any `inputs.*.path` file has been modified after `run_at` in the manifest. Per `artifact-contract.md`, lineage integrity is violated.                                                                                                                         |
| Malformed manifest                                  | The `manifest.json` exists but fails to parse as valid JSON, or is missing required top-level fields (`schema_version`, `run_id`, `plan_slug`, `run_at`).                                                                                                     |
| Malformed findings                                  | The `findings.json` exists but has invalid enumerated values (e.g., `severity` not in the allowed set, `verdict` not in the allowed set) or missing required fields on any finding record. See `findings-schema.md` §Field Documentation for required fields. |
| Missing required input after run claimed completion | The manifest references a source plan or evidence file that no longer exists at the declared path.                                                                                                                                                            |
| Conflicting run                                     | Another run with the same `plan_slug` and `run_id` already produced outputs that differ. See P4 in `workflow-boundaries.md`.                                                                                                                                  |
| Inference artifact                                  | Any artifact whose content was generated by inferring what a missing input would have contained. The skill is prohibited from inference per `workflow-boundaries.md` §5.                                                                                      |

**Downstream actions for `invalid` artifacts:**

| Action                                     | Permitted         | Condition                                                                               |
| ------------------------------------------ | ----------------- | --------------------------------------------------------------------------------------- |
| Base governance promotion on               | No                | Never.                                                                                  |
| Extract learning entries from              | No                | Content may be based on incomplete or corrupted inputs.                                 |
| Consult for debugging                      | Yes               | The failure reason in FAILURE.md is useful for understanding what went wrong.           |
| Delete or archive                          | Operator decision | Only the operator may decide to remove invalid artifacts. The skill never auto-deletes. |
| Re-run compound-review after fixing inputs | Yes               | A new run with a new `run_id` may succeed if the underlying issues are resolved.        |

**Eligible artifact paths:**

- `.sisyphus/reviews/{plan_slug}/{run_id}/FAILURE.md`
- Any output path where the corresponding manifest is malformed or stale.
- Any output path where the corresponding findings contain invalid enumerated values.

---

## 3. Stale Lineage Handling

Stale lineage is a hard stop condition. It means the inputs that were read during the run have changed since the run completed, so the outputs may no longer reflect the current state of the evidence.

### 3.1 Detection Rule

Compare the `run_at` timestamp in the manifest against the last-modified timestamp of every file listed in `inputs.*.path`. If any input file was modified after `run_at`, the lineage is stale.

This mirrors the detection rule in `artifact-contract.md` §Stale Detection Rule and `manifest-schema.md` §Stale Detection.

### 3.2 Classification

A stale run is classified as `invalid`, regardless of any other qualities of its outputs.

### 3.3 Recovery

Stale lineage is not recoverable by re-reading the inputs. The operator must:

1. Confirm the current state of the plan and evidence files.
2. Trigger a new compound-review run (new `run_id`).
3. The new run's outputs will be evaluated for trust class independently.

### 3.4 Prevention

The skill checks for stale lineage during Phase 1 (precondition validation). If detected, the skill writes `FAILURE.md` and stops before producing any outputs. This prevents stale outputs from being written at all.

---

## 4. Malformed Artifact-Contract Output Handling

Malformed output means a file exists at the expected path but does not conform to its schema. This can happen due to disk errors, manual edits, or bugs in the skill.

### 4.1 Manifest Malformation

A manifest is malformed if any of these hold:

- The file is not valid JSON.
- Missing any required top-level field: `schema_version`, `run_id`, `plan_slug`, `run_at`, `inputs`, `outputs`, `lineage`.
- The `inputs` object does not contain `plan` or `evidence_files`.

**Handling:** Classify the entire run as `invalid`. Do not attempt to read other outputs from the same run, because their lineage cannot be verified.

### 4.2 Findings Malformation

Findings are malformed if any of these hold:

- The file is not valid JSON.
- Missing any required top-level field: `schema_version`, `run_id`, `plan_slug`, `findings`.
- Any individual finding record is missing a required field (`id`, `severity`, `owner`, `action_class`, `category`, `title`, `description`, `source_artifacts`, `dedupe_key`, `verdict`).
- Any `severity` value is not in the set `{critical, high, medium, low, informational}`.
- Any `verdict` value is not in the set `{APPROVE, REJECT, CONDITIONAL}`.
- Any `owner` value is not in the set `{agent, human, orchestrator}`.
- Any `action_class` value is not in the set `{test-coverage, code-quality, design, scope, guardrail}`.

**Handling:** Classify the findings file as `invalid`. If the manifest and learning.md are well-formed, they may be individually classified as `reference-only` (manifest provides context, learning.md may have been generated before the findings corruption). The operator should be alerted.

### 4.3 Learning Malformation

A learning.md is malformed if any of these hold:

- Missing the required document header (`# Compound Learning — {plan_slug}`).
- Any learning entry is missing a required field (`Type`, `Tags`, `Applies when`, `Guidance`, `Source`).
- The `Type` value is not `bug-resolution` or `harness-guidance`.

**Handling:** Classify the learning.md as `invalid`. The manifest and findings may still be `authoritative` if they pass their own checks. The learning was one of four outputs; its malformation does not invalidate the rest.

### 4.4 Skill-Draft Malformation

A skill-draft.md is malformed if any of these hold:

- Missing the required document header (`# Skill / Harness Draft — {plan_slug}`).
- Missing the `Source-Artifact Linkage` table.
- Missing `Readiness` field.

**Handling:** Classify the skill-draft as `invalid`. Other outputs from the same run are evaluated independently.

### 4.5 Per-Output Independence

Each output artifact is evaluated for trust class independently. A malformed findings.json does not automatically invalidate the learning.md. However, a malformed manifest DOES invalidate all other outputs from the same run, because the manifest is the lineage anchor.

---

## 5. Missing Input Handling

Missing inputs are handled differently depending on whether they are required or optional. This section expands on the degrade-gracefully policy in `artifact-contract.md` §Failure Rules.

### 5.1 Required Inputs Missing

| Missing Input              | Effect                     | Trust Class       |
| -------------------------- | -------------------------- | ----------------- |
| Plan file (`P1`)           | No run possible.           | Run cannot start. |
| All evidence files (`P2`)  | No synthesis substrate.    | Run cannot start. |
| Ambiguous plan slug (`P3`) | Cannot resolve target.     | Run cannot start. |
| Conflicting run (`P4`)     | Potential data corruption. | Run cannot start. |

When any required input is missing, the skill writes `FAILURE.md` and stops. No outputs are produced. There is nothing to classify.

### 5.2 Optional Inputs Missing (Degrade Gracefully)

| Missing Input                                                    | Effect on Trust Class                                                                                                                                          | Downstream Impact                                                                                                 |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| One facet missing                                                | Still `authoritative` if all other criteria pass.                                                                                                              | `facets_missing` records which facet was absent. Findings that would have come from that facet are simply absent. |
| Two or more facets missing                                       | May still be `authoritative`, but `confidence_reduced: true` is a strong signal. Downstream consumers should weight findings from heavily degraded runs lower. | The run has broader blind spots. Findings may miss issues that the absent facets would have caught.               |
| All four facets missing                                          | `reference-only` at best. The run has no structured review input, only raw evidence and the plan.                                                              | Treat findings as low-coverage observations, not comprehensive review.                                            |
| No notepad directory                                             | `authoritative` if all other criteria pass. Notepads are optional enrichment.                                                                                  | No notepad-derived contextual enrichment in findings.                                                             |
| No notepad files (`learnings.md` and `decisions.md` both absent) | `authoritative` if all other criteria pass.                                                                                                                    | Noted in manifest as warning. No degradation to trust class.                                                      |

### 5.3 Missing Input After Run Completion

If a manifest references a source path that no longer exists (e.g., someone deleted an evidence file after the run completed), the artifact is classified as `invalid`. The lineage chain is broken: the run claimed to read a file that cannot be verified.

---

## 6. Dedupe and Confidence Guidance for Repeated Runs

Multiple compound-review runs for the same `plan_slug` are expected. This section defines how to handle the resulting overlap.

### 6.1 Same `plan_slug`, Different `run_id`

When multiple runs exist for the same plan:

1. **Most recent `authoritative` run is primary.** If the latest run is `authoritative`, its outputs take precedence.
2. **Earlier `authoritative` runs become `reference-only`.** Their outputs are demoted but preserved for historical context.
3. **If the latest run is `invalid`**, fall back to the most recent `authoritative` run. The invalid run's FAILURE.md may explain why.
4. **Never merge across trust classes.** You cannot combine an `authoritative` finding with a `reference-only` finding to create a stronger finding. Each class stands on its own.

### 6.2 Same `dedupe_key` Across Runs

When the same `dedupe_key` appears in findings from different runs for the same `plan_slug`:

1. **Keep the finding from the most recent `authoritative` run.** It reflects the latest evidence and schema.
2. **Record prior occurrences.** Add a `prior_occurrences` array (optional, not in v1 schema) or an Overlap/Deduplication Note in learning.md referencing earlier run_ids.
3. **If the finding's verdict changed between runs** (e.g., APPROVE in run 1, REJECT in run 2), the most recent verdict wins, and the change should be noted. This indicates the issue recurred or was re-evaluated.

### 6.3 Confidence Scoring

Trust class alone does not capture nuance. For governance promotion, consider this confidence matrix:

| Signal                                                                    | Confidence Boost | Confidence Penalty |
| ------------------------------------------------------------------------- | ---------------- | ------------------ |
| All four facets present                                                   | +1               |                    |
| Notepad files present                                                     | +1               |                    |
| `confidence_reduced: false`                                               | +1               |                    |
| Two or more facets missing                                                |                  | -1                 |
| No notepad at all                                                         |                  | -1 (minor)         |
| `confidence_reduced: true`                                                |                  | -1                 |
| Finding reaffirmed across multiple runs (same `dedupe_key`, same verdict) | +2               |                    |
| Finding verdict flipped across runs                                       |                  | -2 (investigate)   |
| Only one evidence file                                                    |                  | -1                 |

Maximum confidence: 5 (all facets + notepads + not reduced + reaffirmed).
Minimum for governance promotion: 2.

Runs below 2 should not be used as sole basis for governance decisions. Pair with human review.

---

## 7. Classification Decision Tree

```
START: Is there a FAILURE.md for this run?
├── Yes → CLASS: invalid (stop)
└── No → Does manifest.json exist and parse?
    ├── No → CLASS: invalid (stop)
    └── Yes → Stale check: any input modified after run_at?
        ├── Yes → CLASS: invalid (stale lineage, stop)
        └── No → Are all required fields present in manifest?
            ├── No → CLASS: invalid (malformed, stop)
            └── Yes → Is findings.json present and valid?
                ├── No → CLASS: invalid (for findings), evaluate other outputs independently
                └── Yes → Is confidence_reduced true?
                    ├── Yes → Are 2+ facets missing?
                    │   ├── Yes → CLASS: reference-only (unless paired with authoritative)
                    │   └── No → CLASS: authoritative (with confidence note)
                    └── No → Is this the most recent authoritative run for this plan_slug?
                        ├── Yes → CLASS: authoritative
                        └── No → CLASS: reference-only (superseded)
```

---

## 8. Governance Promotion Rules

A plan may be promoted through a governance gate (e.g., "ready for merge", "ready for release") when:

1. At least one `authoritative` compound-review run exists for the `plan_slug`.
2. The authoritative run has confidence score >= 2 (see §6.3).
3. No finding in the authoritative run has `verdict: REJECT` with `severity: critical` or `severity: high`.
4. Any `REJECT` findings at `medium` severity have acknowledged mitigations or follow-up issues filed.
5. If `confidence_reduced: true`, the operator has explicitly accepted the reduced coverage.

These rules are recommendations. The human operator always has final say on governance promotion.

---

## 9. Examples from Real Artifacts

### Example A: Confidence-Reduced Run (voy-225-window-shell-split, run 2026-04-16-133347)

**Classification: `reference-only`** (all four facets missing, `confidence_reduced: true`)

| Check                 | Result                                                                                  |
| --------------------- | --------------------------------------------------------------------------------------- |
| FAILURE.md exists?    | No                                                                                      |
| manifest.json exists? | Yes (at `.sisyphus/reviews/voy-225-window-shell-split/2026-04-16-133347/manifest.json`) |
| Stale check           | Pass (run completed, no inputs modified after)                                          |
| findings.json valid?  | Yes                                                                                     |
| learning.md valid?    | Yes, 3 entries with proper Type, Tags, Applies when, Guidance, Source fields            |
| confidence_reduced    | `true` — all four facets missing (`f1`, `f2`, `f3`, `f4`)                               |
| Facets present?       | None — manifest `facets` is `{}`, `facets_missing` lists all four                       |
| Decision tree path    | §7: confidence_reduced=true → 2+ facets missing → **reference-only**                    |

**Downstream:** This learning.md may enrich governance context but cannot independently drive promotion decisions (§2.1 exception for all-facets-missing). When paired with authoritative runs from other plans (e.g., voy-226 runs), the combined evidence may support promotion per §7 decision tree "unless paired with authoritative" clause. When treated as pre-governance adoptions (see `exemplar-mappings.md` §Bootstrap Note), these runs provide valid historical evidence for already-adopted rules.

### Example B: Stale Lineage Failure (voy-223-filemanager-packageization, run 2026-04-16-133347)

**Classification: `invalid`**

| Check              | Result                                                                             |
| ------------------ | ---------------------------------------------------------------------------------- |
| FAILURE.md exists? | Yes                                                                                |
| Failure reason     | P5: plan mtime (2026-04-13T19:12:39) > latest evidence mtime (2026-04-13T19:02:18) |
| Stale lineage      | Plan was modified after evidence was produced                                      |

**Downstream:** This run cannot be used for governance promotion. The plan changed after the evidence was gathered, so any findings would be based on a mismatched input set. A new run must be triggered after confirming the current state of plan and evidence.

### Example C: Missing Evidence Failure (pages-file-manager-issue-plans, run 2026-04-16-133347)

**Classification: `invalid`**

| Check              | Result                                                                                |
| ------------------ | ------------------------------------------------------------------------------------- |
| FAILURE.md exists? | Yes                                                                                   |
| Failure reason     | P2: no evidence files matching `task-{N}-*.*` found                              |
| Additional context | This is a governance/sequencing plan, not an execution plan. It has no task evidence. |

**Downstream:** This run cannot produce findings. The plan type (governance plan without task evidence) is structurally incompatible with compound-review synthesis. Not a bug, just a mismatch between plan type and workflow requirements.

---

## 10. Relationship to Other Reference Documents

| Reference                | Relationship                                                                                                                                               |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `artifact-contract.md`   | Defines the artifact families and failure rules that this taxonomy classifies. The contract is the "what"; this taxonomy is the "how much do we trust it." |
| `workflow-boundaries.md` | Defines preconditions (P1-P6, OP1-OP3) that determine whether a run even starts. This taxonomy handles what happens after a run completes or fails.        |
| `findings-schema.md`     | Defines the structure of findings that are classified. Malformed findings are `invalid`.                                                                   |
| `learning-schema.md`     | Defines the structure of learning documents that are classified.                                                                                           |
| `manifest-schema.md`     | Defines the structure of the manifest, which is the primary classification anchor.                                                                         |
| `skill-draft-schema.md`  | Defines the structure of skill drafts that are classified.                                                                                                 |

---

## Schema Version History

| Version | Date       | Change          |
| ------- | ---------- | --------------- |
| 1.0     | 2026-04-17 | Initial schema. |
