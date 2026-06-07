# OpenCode + OMO Adapter Design

This skill is usable without runtime hooks. The project-local OpenCode adapter lives at `.opencode/plugins/sisyphus-wiki.js` and automates candidate capture without editing protected `opencode.json`.

## Separation of responsibilities

| Layer          | Responsibility                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Skill          | Decides what is durable knowledge and how to classify it.                                                                 |
| Scripts        | Write entries, update indexes, append graph events, validate schemas.                                                     |
| Adapter/plugin | Observes OpenCode/OMO events and writes sanitized turn-level session ledgers/candidates for later promotion into entries. |

## Turn capture model

The adapter must treat the canonical OpenCode session store as the source of truth for full transcripts. `.sisyphus/knowledge/sessions/` is only a compact extraction cache. Prefer dedicated OpenCode plugin hooks over the generic event stream:

| OpenCode hook / event                                  | Adapter behavior                                                                     |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `chat.message`                                         | Append `turn.user`; mark as `candidate` for later durable-knowledge extraction.      |
| `experimental.text.complete`                           | Append final `turn.assistant`; mark as `candidate`. Do not capture hidden reasoning. |
| `tool.execute.after`                                   | Append `turn.tool` with tool name, status, sanitized input, and short output only.   |
| generic `event` fallback for `todo.updated`            | Append `turn.todo` with compact todo content/status/priority when available.         |
| generic `event` fallback for `session.created/updated` | Append `turn.session` metadata such as title, parent ID, agent, and model.           |
| TUI toast, file watcher, token delta, other telemetry  | Skip. These remain in the canonical session/runtime logs, not the wiki.              |

## Adapter constraints

- Do not require Voyager-specific paths or skills.
- Do not write plan-scoped evidence from the adapter; only link to it.
- Do not capture secrets or full sensitive payloads.
- Do not create high-confidence entries from raw telemetry without agent/user interpretation.
- Do not treat `inbox/pending-extractions.jsonl` as curated knowledge. It is a queue for later promotion.
- Do not write `unknown-session` ledgers. Events without a session ID are telemetry noise for wiki purposes.
- Do not lowercase session IDs in filenames; preserve IDs enough to link back to the canonical session store.
- Use flat hook keys from `@opencode-ai/plugin` such as `"chat.message"` and `"experimental.chat.system.transform"`; do not use nested hook objects.

## Script surface

The skill bundles deterministic helpers:

```text
wiki-write    --type finding --title "..." --tags traceability,review --source plan:slug
wiki-session-event --session-id ses_x --event turn.user --summary "..." --candidate
wiki-query    --tag traceability --source plan:slug --json
wiki-index    --rebuild
wiki-validate --root .sisyphus/knowledge
```

Scripts should emit JSON to stdout, diagnostics to stderr, and use non-zero exits for validation failures.

## Activation

OpenCode loads project-local plugin files from `.opencode/plugins/` at startup. Restart OpenCode after adding or changing `.opencode/plugins/sisyphus-wiki.js`.
