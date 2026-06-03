# OpenCode + OMO Adapter Design

This skill is usable without runtime hooks. The project-local OpenCode adapter lives at `.opencode/plugins/sisyphus-wiki.js` and automates candidate capture without editing protected `opencode.json`.

## Separation of responsibilities

| Layer          | Responsibility                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------------- |
| Skill          | Decides what is durable knowledge and how to classify it.                                                     |
| Scripts        | Write entries, update indexes, append graph events, validate schemas.                                         |
| Adapter/plugin | Observes OpenCode/OMO events and writes sanitized session/candidate streams for later promotion into entries. |

## Event model

The adapter maps harness events to candidate streams:

| OpenCode event                                         | Adapter behavior                                                          |
| ------------------------------------------------------ | ------------------------------------------------------------------------- |
| `message.updated`, `message.part.updated`              | Append sanitized session event; mark as candidate.                        |
| `session.compacted`, `session.idle`, `session.updated` | Append lifecycle event; mark useful compaction/idle states as candidates. |
| `todo.updated`, `file.edited`, `tool.execute.after`    | Append sanitized session event; mark as candidate for later extraction.   |
| Other events                                           | Append observed session event only.                                       |

## Adapter constraints

- Do not require Voyager-specific paths or skills.
- Do not write plan-scoped evidence from the adapter; only link to it.
- Do not capture secrets or full sensitive payloads.
- Do not create high-confidence entries from raw telemetry without agent/user interpretation.
- Do not treat `inbox/pending-extractions.jsonl` as curated knowledge. It is a queue for later promotion.

## Script surface

The skill bundles deterministic helpers:

```text
wiki-write    --type finding --title "..." --tags traceability,review --source plan:slug
wiki-session-event --session-id ses_x --summary "..." --candidate
wiki-query    --tag traceability --source plan:slug --json
wiki-index    --rebuild
wiki-validate --root .sisyphus/knowledge
```

Scripts should emit JSON to stdout, diagnostics to stderr, and use non-zero exits for validation failures.

## Activation

OpenCode loads project-local plugin files from `.opencode/plugins/` at startup. Restart OpenCode after adding or changing `.opencode/plugins/sisyphus-wiki.js`.
