# Voyager Dev Structure Validation

Use this after changing `.agents/skills/voyager-dev/**`.

## Checks

- Top-level `../../AGENTS.md` remains namespace guidance and there is no top-level skill file.
- `../SKILL.md` remains the only broad trigger surface.
- Role folders contain thin entry points and do not duplicate long shared policies.
- Source-of-truth files live under the owning role's `references/` directory unless a deliberate path migration updates all links.
- `skill-map.md` mentions every role entry point.
- Validate each role skill file that follows directory-name constraints; note that `../SKILL.md` intentionally uses `name: voyager-dev` as the public entry-point name.
- `git diff --check -- .agents/skills/voyager-dev` reports no whitespace errors.

## Must not

- Do not create two canonical homes for the same policy.
- Do not hide implementation rules only inside a role file if the parent workflow still needs them.
