# Governance Cadence and Evidence Freshness Policy

**Version:** 1.0
**Scope:** Defines when to run `compound-review` and when to run cross-plan governance sweeps. Governs the operating rhythm for Stage 2 in the lifecycle defined by `lifecycle-contract.md`.
**Source of truth for:** All agents and human operators who decide when to trigger compound-review, when to perform cross-plan sweeps, and which runs count as sweep-eligible.
**Normative references:** `lifecycle-contract.md`, `evidence-trust-taxonomy.md`, `promotion-policy.md`, `artifact-contract.md`

---

## 1. Purpose

Without a defined cadence, governance runs either pile up unreviewed or get skipped entirely. Operators forget which plans have been compounded, and stale evidence accumulates without anyone noticing. This policy replaces ad hoc judgment with two deterministic triggers: one per-plan, one cross-plan.

The cadence is event-driven. It does not run on a wall-clock schedule. It runs when the right conditions are met.

---

## 2. Trigger 1: Per-Plan Post-Completion Review

### 2.1 When It Fires

After every completed Sisyphus Work cycle where the plan has been marked complete with final evidence artifacts under `.sisyphus/evidence/{plan_slug}/`.

Concretely: when the operator confirms Work is done and the Stage 1 handoff conditions in `lifecycle-contract.md` §Stage 1 hold (all tasks checked, at least one evidence file exists, operator has confirmed completion), the operator may trigger `compound-review` for that plan.

### 2.2 What It Produces

A single governance bundle per run, written to:

- `.sisyphus/reviews/{plan_slug}/{run_id}/manifest.json`
- `.sisyphus/reviews/{plan_slug}/{run_id}/findings.json`
- `.sisyphus/reviews/{plan_slug}/{run_id}/learning.md`
- `.sisyphus/reviews/{plan_slug}/{run_id}/skill-draft.md`

### 2.3 Purpose

Synthesize findings from one plan's evidence, compound learnings, and produce a patch spec for Stage 3. This is the default, routine cadence. Every completed plan gets reviewed.

### 2.4 Who Triggers It

The human operator, manually. `compound-review` is never auto-triggered. Per `workflow-boundaries.md`, the skill is manual-trigger only.

---

## 3. Trigger 2: Cross-Plan Governance Sweep

### 3.1 When It Fires

A cross-plan sweep is triggered when **either** of these conditions is met, whichever comes first:

| Condition                | Threshold                                                               | How to Check                                                                                                                           |
| ------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **Accumulation trigger** | 3 new `authoritative` compound runs have completed since the last sweep | Count runs with trust class `authoritative` (per `evidence-trust-taxonomy.md` §2.1) whose `run_at` is after the last sweep's `run_at`. |
| **Time trigger**         | 14 days have passed since the last sweep                                | Compare today's date against the `run_at` timestamp of the most recent sweep.                                                          |

### 3.2 What "New" Means

A run counts as "new" for the accumulation trigger when:

1. Its `run_at` timestamp is after the `run_at` of the most recent sweep.
2. It is classified as `authoritative` per `evidence-trust-taxonomy.md` §2.1.

A run does NOT count when:

- It is `reference-only` (superseded by a newer authoritative run, or degraded confidence with 2+ missing facets).
- It is `invalid` (FAILURE.md exists, stale lineage, malformed outputs).
- Its evidence is stale (any input file modified after `run_at`).

### 3.3 What a Sweep Does

A cross-plan sweep reviews all accumulated compound artifacts across all plan slugs:

1. Scan all `findings.json` files under `.sisyphus/reviews/` for recurrence patterns (matching `dedupe_key` values across plan slugs).
2. Scan all `learning.md` files under `.sisyphus/reviews/*/*/learning.md` for cross-plan category/tag overlap.
3. Apply the promotion decision rules from `promotion-policy.md` §5 to determine which findings qualify for CREATE NEW, EXTEND EXISTING, or STAY LOCAL-ONLY.
4. Run the conflict detection algorithm from `promotion-policy.md` §6.
5. Produce a sweep report with promotion recommendations.

### 3.4 Sweep Output

The sweep produces:

| Artifact                  | Path                                                     |
| ------------------------- | -------------------------------------------------------- |
| Sweep manifest            | `.sisyphus/reviews/_sweeps/{run_id}/manifest.json`       |
| Cross-plan findings       | `.sisyphus/reviews/_sweeps/{run_id}/findings.json`       |
| Promotion recommendations | `.sisyphus/reviews/_sweeps/{run_id}/promotion-report.md` |

The `_sweeps/` directory separates sweep-level artifacts from per-plan artifacts.

### 3.5 Who Triggers It

The human operator, manually. The operator checks whether the accumulation or time trigger condition is met, then triggers the sweep. Agents may report the current state of trigger conditions but cannot auto-trigger.

---

## 4. Freshness Rules

### 4.1 Only Authoritative Runs Count Toward Sweep Triggers

The accumulation trigger counts only `authoritative` runs. This is not a pedantic distinction. `reference-only` and `invalid` runs do not carry enough weight to justify triggering a cross-plan review.

| Trust class                                     | Counts toward accumulation trigger? | Reason                                                                                                                                |
| ----------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `authoritative`                                 | Yes                                 | Complete, validated, trustworthy.                                                                                                     |
| `authoritative` with `confidence_reduced: true` | Yes                                 | Confidence reduction degrades coverage but does not disqualify from authoritative status. Per `evidence-trust-taxonomy.md` §2.1 note. |
| `reference-only`                                | No                                  | Superseded, degraded, or insufficient for sole basis.                                                                                 |
| `invalid`                                       | No                                  | Failed, stale, or malformed. No governance value.                                                                                     |

### 4.2 Stale Evidence Is Excluded from Sweep Eligibility

A run whose evidence has been modified after `run_at` is classified as `invalid` per `evidence-trust-taxonomy.md` §3.2. Invalid runs do not count toward the accumulation trigger.

Even if a run was originally `authoritative`, if its evidence files are modified after `run_at`, the run becomes stale and is reclassified as `invalid`. It is immediately removed from the sweep-eligible count.

### 4.3 Freshness Check Procedure

Before counting runs toward the accumulation trigger:

1. Read each candidate run's `manifest.json` to get `run_at`.
2. For each `inputs.*.path` in the manifest, check the file's last-modified timestamp.
3. If any input was modified after `run_at`, exclude the run.
4. If the manifest is missing or malformed, exclude the run (it is `invalid`).

### 4.4 What to Do When a Run Goes Stale

When a previously-counted run becomes stale:

1. Remove it from the accumulation count.
2. If this drops the count below the threshold, the sweep does not trigger.
3. The operator should re-run `compound-review` for the affected plan to produce fresh authoritative output.

---

## 5. Sweep Reset

A sweep resets the accumulation counter to zero. After a sweep completes:

1. Record the sweep's `run_at` as the new baseline timestamp.
2. All subsequent accumulation counts start from this baseline.
3. Check adopted rules and skills whose source dedupe keys appear in the sweep window. Flag each as `still-useful`, `needs-revision`, `candidate-rollback`, or `no-recent-signal`.
4. The 14-day clock restarts from the sweep's `run_at`.

If a sweep is triggered by the time condition (14 days) but no new authoritative runs have accumulated, the sweep still runs but produces a "no new findings" report. This confirms the governance system is alive even during quiet periods.

For adopted-rule health checks, absence of the original dedupe key is not automatically bad; it may mean the rule worked. Rollback is considered only when the adopted harness creates noise, conflicts with current structure, or causes new regressions.

---

## 6. Interaction with Promotion Policy

The sweep is the primary mechanism for detecting cross-plan recurrence, which is the strongest signal in `promotion-policy.md` §3.2 (cross-plan recurrence adds +1 bonus to promotion confidence).

Per-plan reviews may detect same-plan recurrence. Cross-plan sweeps detect cross-plan recurrence. Both feed into the same promotion scoring system.

| Trigger type     | Recurrence type detected                             | Promotion bonus                   |
| ---------------- | ---------------------------------------------------- | --------------------------------- |
| Per-plan review  | Same `plan_slug`, different `run_id`                 | Standard (+2 per independent run) |
| Cross-plan sweep | Different `plan_slug`, matching `dedupe_key` or tags | Cross-plan bonus (+1)             |

---

## 7. Edge Cases

### 7.1 First Sweep (No Prior Sweep Exists)

When no prior sweep has been recorded:

- The accumulation trigger counts all authoritative runs in `.sisyphus/reviews/`.
- The time trigger starts from the date of the earliest authoritative run.
- The first sweep establishes the baseline for all future trigger calculations.

### 7.2 Multiple Plans Completing Simultaneously

If multiple plans complete around the same time, each gets its own per-plan review. The accumulation counter increments once per completed authoritative run. Three plans completing in quick succession could trigger a sweep immediately.

### 7.3 Operator-Initiated Sweep Out of Cadence

The operator may trigger a sweep at any time, regardless of trigger conditions. This does not reset the accumulation counter or the time clock. Only cadence-triggered sweeps reset the counters.

### 7.4 Runs That Are Authoritative but Confidence-Reduced

A run with `confidence_reduced: true` still counts toward the accumulation trigger. The confidence reduction is a quality signal for downstream consumers, not a disqualification from the cadence system. Per `evidence-trust-taxonomy.md` §2.1, confidence reduction "degrades the run's coverage but does not disqualify it from `authoritative` status."

---

## 8. Visual Cadence Flow

```
┌────────────────────────────┐
│  Plan completes Work cycle  │
│  (Stage 1 handoff met)      │
└──────────────┬─────────────┘
               │
               ▼
┌────────────────────────────┐
│  Operator triggers          │
│  compound-review            │
│  (Per-plan, Trigger 1)      │
│                             │
│  Produces: manifest,        │
│  findings, learning, draft  │
└──────────────┬─────────────┘
               │
               ▼
┌────────────────────────────┐
│  Is this run               │
│  authoritative?             │
│                             │
│  Yes → Add to sweep count  │
│  No → Skip                  │
└──────────────┬─────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│  Check sweep trigger conditions:         │
│                                          │
│  A. Accumulation count ≥ 3?              │
│  B. Days since last sweep ≥ 14?          │
│                                          │
│  Either true → trigger cross-plan sweep  │
│  Neither true → wait                     │
└──────────────┬───────────────────────────┘
               │
               ▼ (when triggered)
┌────────────────────────────┐
│  Cross-Plan Governance      │
│  Sweep (Trigger 2)          │
│                             │
│  Scans all reviews/,        │
│  compound/, drafts/         │
│                             │
│  Produces: sweep manifest,  │
│  cross-plan findings,       │
│  promotion report           │
│                             │
│  Resets accumulation count  │
│  and 14-day clock           │
└────────────────────────────┘
```

---

## 9. Why This Cadence Exists

The governance system needs regular review without constant overhead. Per-plan reviews catch issues while context is fresh. Cross-plan sweeps catch patterns that span multiple work cycles, which is where the most valuable governance insights live (scope drift, repeated mistakes, emerging conventions).

The dual-trigger design (accumulation OR time) handles two regimes: active periods where plans complete rapidly and quiet periods where weeks pass between plans. In active periods, the accumulation trigger fires before 14 days elapse. In quiet periods, the time trigger ensures governance does not go stale even with zero new runs.

Requiring 3 authoritative runs (not 1, not 2) before a sweep means the sweep has enough cross-plan signal to produce meaningful promotion recommendations. A single run cannot establish a pattern. Two runs suggest correlation but may be coincidence. Three runs is the minimum for a defensible cross-plan finding.

---

## 10. Relationship to Other Reference Documents

| Reference                    | Relationship                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------------ |
| `lifecycle-contract.md`      | Defines the three-stage lifecycle. This cadence governs when Stage 2 runs.                             |
| `evidence-trust-taxonomy.md` | Defines trust classes. Only `authoritative` runs count toward sweep triggers.                          |
| `promotion-policy.md`        | Defines promotion thresholds. Cross-plan sweeps feed recurrence data into promotion scoring.           |
| `artifact-contract.md`       | Defines artifact families and stale detection. Freshness rules use the stale check from this contract. |
| `workflow-boundaries.md`     | Defines compound-review boundaries. This cadence operates within those boundaries.                     |

---

## Schema Version History

| Version | Date       | Change          |
| ------- | ---------- | --------------- |
| 1.0     | 2026-04-17 | Initial policy. |
