# Sisyphus Wiki Skill Package

`sisyphus-wiki` is a reusable, cross-project skill for maintaining a project-local LLM wiki under `.sisyphus/knowledge/`.

## Boundaries

- Keep this skill independent from Voyager-specific workflows.
- Keep runtime artifacts under `.sisyphus/knowledge/`, not under plan-scoped `evidence/`, `notepads/`, or `reviews/`.
- Treat `.sisyphus/knowledge/` as local-only runtime state unless the user explicitly asks to export it.

## Package structure

- `SKILL.md` — main skill entry point.
- `references/schema.md` — canonical data shape for entries and graph metadata.
- `references/relation-taxonomy.md` — allowed edge relation names.
- `references/write-policy.md` — durable-knowledge capture rules.
- `references/retrieval-policy.md` — lookup rules before planning or writing.
- `references/opencode-omo-adapter.md` — future plugin/adapter design notes.
- `evals/evals.json` — initial behavior checks for the skill.

## Maintenance rules

- Update `references/schema.md` before adding new entry fields.
- Update `references/relation-taxonomy.md` before using new relation names.
- Keep `SKILL.md` concise; move detailed policy to references.
