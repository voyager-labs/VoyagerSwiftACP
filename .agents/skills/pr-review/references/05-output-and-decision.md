# 05 — Output and Review Decision

Run after `04-repository-aware-review-execution.md`.

## Output contract

Use `.greptile/rules.md` §Comment format and §Review output and decision as the authoritative output contract. For large or partial reviews, use `references/review-playbook.md` §Coverage Statement Format.

Do not fabricate findings to justify the review. A clean review is a valid outcome.

## Non-blocking observations

- Use `[Observation]` label exclusively.
- Never use P0/P1/P2/P3/nit for non-blocking items.
- Record design differences that were explicitly checked but are not findings.
- Observations have no effect on review decision. Omit them if noisy.

## Verification evidence separation

- `PR-provided evidence:` — verification commands/claims from PR body.
- `Reviewer-rerun evidence:` — commands actually run during review, or `none`.
- `Suggested verification follow-up:` — runtime verification commands/user flows when needed.

## Review footer

End every review output with:

- Reviewed commit SHA, or `diff-only, no local checkout`.
- Base branch.
- Context used: policy file, playbook areas, background agents.
- Unresolved gaps.

## Self-check checklist

Complete this before finalizing the review decision:

- [ ] `.greptile/rules.md` read
- [ ] PR auto-review skip conditions checked
- [ ] PR metadata + changed files collected
- [ ] Diff size / large-PR classification done
- [ ] Background task results collected and reconciled
- [ ] PR head / local worktree match or diff-only scope stated
- [ ] P0/P1 judgments align with `.greptile/rules.md`
- [ ] Local verification status and rationale stated
