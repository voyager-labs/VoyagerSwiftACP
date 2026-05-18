# Voyager Dev Orchestration Workflow

## Steps

1. **Classify** — identify whether the task is scaffold, decompose, observation-refactor, reuse-guard, implementation, review, or verification.
2. **Discover read-only** — inspect owners, reducer/effect routes, cancellation boundaries, reusable symbols, and focused test surface before editing.
3. **Route** — choose role entry points from `skill-map.md`.
4. **Load references** — read the selected role's reference files and any cross-role references listed in `skill-map.md`.
5. **Execute** — perform the smallest implementation/review/verification step that matches the selected role.
6. **Verify** — run `../../verifier/verification/SKILL.md` and any role-specific checks.
7. **Report** — summarize role decisions, touched files, commands run, and remaining risks.

## Anti-absorption rule

The orchestrator must not absorb detailed implementation, planning, review, or verification instructions. If detailed guidance grows, move it to the owning role entry point or shared reference.
