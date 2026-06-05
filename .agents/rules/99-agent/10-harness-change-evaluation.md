---
description: "Evaluate harness changes before adoption so weak rules/skills can be rejected, revised, or rolled back."
globs: ".agents/**"
---

# Harness Change Evaluation

## Must

- Define the intended behavioral improvement before adoption.
- Run the smallest relevant evaluation set for the changed harness surface.
- Compare new behavior against an explicit baseline: previous skill/rule version, no-skill behavior, or documented current behavior.
- Use explicit regression budgets instead of subjective "seems better" judgments.
- Record an adoption verdict: `adopt`, `revise`, `rollback`, or `defer`.
- Keep local run outputs in `.sisyphus/` or skill workspaces; promote only reusable harness changes.

## Must not

- Treat adding more rules, references, or eval prompts as inherently better.
- Adopt a harness change when evals show lower correctness, more noise, stale routing, or unclear ownership.
- Use only self-assessment when objective eval fixtures or prior behavior can be compared.
- Delete local evidence to make a bad adoption look clean.

## Execution steps

1. **State the hypothesis:** describe what future agent behavior should improve and which regression it should prevent.
2. **Select evals:** choose existing `evals/evals.json` cases for touched skills, or add focused cases before adoption.
3. **Capture baseline:** use the previous file version, existing behavior, or a no-skill run as the baseline.
4. **Run or simulate evaluation:** collect pass/fail expectations, qualitative notes, and any token/time tradeoff if available. Use one smoke run for fast checks, three runs for adoption gates when nondeterminism matters, and five runs for release-sensitive skills.
5. **Apply default budgets:** strict safety/path/ownership cases must pass all runs; normal golden cases should pass at least 2/3 runs; pass-rate must not drop more than 0.03 from baseline unless the operator accepts a documented tradeoff.
6. **Update history when available:** append or reference a benchmark summary so future work can compare against this adoption.
7. **Decide:**
    - `adopt` when correctness improves or the change closes a verified gap without regressions.
    - `revise` when the direction is useful but evals expose gaps.
    - `rollback` when the change worsens correctness, routing, or review noise.
    - `defer` when evidence is insufficient.
8. **Record evidence:** summarize baseline, new result, verdict, and rollback path in task evidence or the PR body.

## Verification

- Every harness adoption has a stated hypothesis and at least one relevant eval or explicit rationale for why no eval applies.
- Skill changes either include/refresh `evals/evals.json` or state which existing evals cover the change.
- Regression or no-improvement outcomes are revised, rolled back, or deferred before adoption.
- Adoption evidence includes the baseline, candidate result, budget result, and run count.
- The rollback path names the exact file(s) or commit to revert.
