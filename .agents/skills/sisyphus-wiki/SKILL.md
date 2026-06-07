---
name: sisyphus-wiki
description: "Maintains a project-local LLM wiki and cross-session knowledge graph under .sisyphus/knowledge. Use when recording plan-independent decisions, review learnings, user preferences, rejected approaches, reusable patterns, or links between sessions, plans, evidence, reviews, and skills. Triggers on: LLM wiki, knowledge graph, agent memory, scribe, traceability, cross-session notes, planless artifacts, always record."
compatibility: opencode
metadata:
    runtime_root: .sisyphus/knowledge
    scope: cross-project
    output: knowledge-graph
---

# Sisyphus Wiki

Use this skill to maintain a project-local LLM wiki: a cross-session knowledge graph that records durable decisions, findings, patterns, preferences, and traceability links outside any single Sisyphus plan.

## When to use this skill

- The user asks for an LLM wiki, knowledge graph, agent memory, scribe layer, or always-on recording design.
- Work produces a reusable decision, correction, rejected approach, user preference, review learning, or harness improvement that should survive session boundaries.
- A planless or ad-hoc conversation influences one or more plans, evidence files, reviews, skills, rules, code paths, or future work.
- You need to retrieve prior project-local knowledge before planning, implementing, reviewing, or explaining related work.

## Not for

- Replacing `.sisyphus/plans/`, `.sisyphus/evidence/`, `.sisyphus/notepads/`, or `.sisyphus/reviews/`.
- Logging every raw tool call. The wiki stores distilled knowledge, not exhaustive telemetry.
- Treating notes as more authoritative than source code, tests, docs, or explicit user instructions.
- Voyager-specific workflow routing. Use `voyager-dev` for Voyager macOS TCA/FSD work.

## Runtime layout

Write runtime artifacts under `.sisyphus/knowledge/`:

```text
.sisyphus/knowledge/
├── index.json
├── graph.jsonl
├── entries/
│   └── YYYY-MM-DD-<entry-slug>.md
├── sessions/
│   └── <session-id>.jsonl
└── inbox/
    └── pending-extractions.jsonl
```

This directory is local runtime state. Do not stage or commit it unless the user explicitly asks to export knowledge artifacts.

## Automation model

The skill supports three automation levels:

1. **Manual capture** — the agent reads this skill and writes durable entries with the schema.
2. **Scripted capture** — `scripts/wiki-*.ts` write, query, validate, and index knowledge artifacts deterministically.
3. **OpenCode/OMO turn capture** — `.opencode/plugins/sisyphus-wiki.js` records sanitized turn-level summaries and durable candidates into `.sisyphus/knowledge/sessions/` and `.sisyphus/knowledge/inbox/` without editing `opencode.json`.

Automatic turn capture is a candidate stream, not final truth. It must not duplicate raw session transcripts or telemetry; promote candidates into entries only when they satisfy `references/write-policy.md`.

## Workflow

1. **Classify the knowledge action**
    - `capture`: create a new entry from a decision, finding, preference, pattern, correction, or open question.
    - `link`: connect existing entries to sessions, plans, evidence, reviews, skills, rules, files, or other entries.
    - `retrieve`: inspect related entries before work.
    - `curate`: update stale links, mark superseded entries, or normalize metadata.

2. **Retrieve before writing**
    - Check `references/retrieval-policy.md`.
    - Search by tags, source IDs, affected paths, plan slugs, skill names, and relation targets.
    - Prefer linking to an existing entry when the new information extends it; create a new entry when the knowledge has its own durable title and lifecycle.

3. **Write the entry**
    - Follow `references/schema.md` for frontmatter and body shape.
    - Use `.sisyphus/knowledge/entries/YYYY-MM-DD-<slug>.md`.
    - Keep body concise: context, durable insight, implications, and next action.
    - Prefer `scripts/wiki-write.ts` for deterministic writes when possible.

4. **Update graph metadata**
    - Add or update the node in `.sisyphus/knowledge/index.json`.
    - Append relation events to `.sisyphus/knowledge/graph.jsonl`.
    - Use relation names from `references/relation-taxonomy.md`; do not invent relation types casually.
    - Use `scripts/wiki-index.ts --rebuild` if entries are edited manually.

5. **Link back to scoped artifacts**
    - If the knowledge came from a plan, evidence, notepad, review, session, skill, rule, file, PR, issue, or command, record that in `sources` or `relations`.
    - Do not move plan-scoped artifacts into knowledge. Link to them.

6. **Report what changed**
    - Summarize the entry ID, title, tags, and key relations.
    - Mention when no entry was written because the information was transient or already captured.

## Entry types

Use these `type` values unless a reference update explicitly expands the schema:

- `decision` — a chosen direction, policy, or tradeoff.
- `finding` — a discovered bug, traceability gap, review result, or system issue.
- `pattern` — a reusable implementation, testing, review, or harness pattern.
- `preference` — a durable user preference or team convention.
- `question` — unresolved design or product question worth revisiting.
- `reference` — pointer to external docs, repositories, specs, or prior work.
- `proposal` — proposed rule, skill, plugin, or workflow improvement.

## Common mistakes

- Do not create `__adhoc__` folders under every plan-scoped category. Planless knowledge belongs in `.sisyphus/knowledge/`.
- Do not duplicate entire evidence files inside wiki entries. Summarize and link.
- Do not write low-signal diary entries for every command. Capture durable knowledge only.
- Do not store raw OpenCode event streams in `sessions/`; use turn-level summaries and link back to the canonical session store.
- Do not use vague relation names like `connected`. Prefer `affects`, `motivates`, `resolved_by`, or `evidence_for`.
- Do not treat graph links as proof. They are traceability pointers that still need source verification.

## Reference files

- `references/schema.md` — entry, index, graph event, and source schemas.
- `references/relation-taxonomy.md` — allowed relation types and meanings.
- `references/write-policy.md` — when to write, update, or skip wiki entries.
- `references/retrieval-policy.md` — how to search and consume wiki knowledge before work.
- `references/opencode-omo-adapter.md` — plugin-ready adapter design for OpenCode + OMO.
