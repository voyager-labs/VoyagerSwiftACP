# Retrieval Policy

Use this policy before writing new entries or before starting related non-trivial work.

## Retrieval triggers

Retrieve existing knowledge when the task mentions:

- A previous decision, review, bug, plan, session, or rejected approach.
- Sisyphus artifacts, compound review, evidence, notepads, plans, or review facets.
- Agent harness design, skill authoring, recording, traceability, or knowledge graph work.
- A domain tag likely to exist in the wiki, such as `tca`, `auth`, `verification`, `traceability`, or `compound-review`.

## Lookup order

1. Read `.sisyphus/knowledge/index.json` if present.
2. Search candidate nodes by tag, title, affected path, plan slug, source ID, or skill name.
3. Read the smallest set of matching entry files.
4. If `index.json` is missing or stale, inspect `.sisyphus/knowledge/entries/` directly and rebuild mentally or with a future index script.
5. Use `graph.jsonl` when mutation history matters.

## Consumption rules

- Treat wiki knowledge as advisory context, not proof.
- Verify claims against source code, tests, docs, or linked artifacts before acting on them.
- Prefer entries with `confidence: high` and explicit `verified_by` relations.
- If two entries conflict, follow the one that is newer only after checking `supersedes`, `contradicts`, and source evidence.

## Retrieval output

When retrieval materially affects work, mention:

- Entry IDs consumed.
- Key decision or pattern used.
- Any stale, contradictory, or low-confidence entries ignored.
