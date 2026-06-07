# Sisyphus Wiki Schema

This reference defines the canonical shape for `.sisyphus/knowledge/` artifacts.

## Runtime layout

```text
.sisyphus/knowledge/
├── index.json
├── graph.jsonl
├── entries/YYYY-MM-DD-<entry-slug>.md
├── sessions/<session-id>.jsonl
└── inbox/pending-extractions.jsonl
```

## Entry file

Each knowledge entry is a Markdown file with YAML frontmatter.

```markdown
---
id: kw-20260603-verdict-history-gap
title: REJECT to FIX lifecycle is missing from structured findings
type: finding
status: active
created_at: 2026-06-03T00:00:00+09:00
updated_at: 2026-06-03T00:00:00+09:00
confidence: medium
tags: [traceability, compound-review, sisyphus]
sources:
    - type: session
      id: ses_example
    - type: plan
      id: voy-298-auth-handoff-local-verification
relations:
    - type: motivates
      target: kw-20260603-sisyphus-wiki-proposal
    - type: example_of
      target: kw-20260603-codingkeys-auth-fix
affected:
    - type: skill
      id: compound-review
    - type: runtime_path
      id: .sisyphus/reviews/
---

## Context

Short source context.

## Durable insight

The reusable knowledge to preserve.

## Implications

How this affects future work.

## Next action

Optional follow-up.
```

## Required frontmatter fields

| Field        | Meaning                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------- |
| `id`         | Stable unique ID. Prefer `kw-YYYYMMDD-<slug>`; add a short suffix if needed.                |
| `title`      | Human-readable title.                                                                       |
| `type`       | One of `decision`, `finding`, `pattern`, `preference`, `question`, `reference`, `proposal`. |
| `status`     | `active`, `superseded`, `resolved`, or `archived`.                                          |
| `created_at` | ISO-8601 timestamp.                                                                         |
| `updated_at` | ISO-8601 timestamp.                                                                         |
| `confidence` | `low`, `medium`, or `high`.                                                                 |
| `tags`       | Lowercase kebab-case tags.                                                                  |
| `sources`    | Source artifacts or sessions that produced the knowledge.                                   |
| `relations`  | Graph edges from this entry to other nodes.                                                 |
| `affected`   | Plans, files, skills, rules, docs, reviews, or runtime paths influenced by this entry.      |

## Source object

```yaml
- type: session | plan | evidence | notepad | review | skill | rule | file | issue | pr | external
  id: string
  path: optional-string
  note: optional-string
```

## Relation object

```yaml
- type: relates_to | derived_from | affects | motivates | supersedes | contradicts | resolved_by | evidence_for | verified_by | example_of
  target: string
  note: optional-string
```

## index.json

`index.json` is the compact lookup registry. It should be regenerated or updated whenever entries change.

```json
{
    "version": 1,
    "updated_at": "2026-06-03T00:00:00+09:00",
    "nodes": [
        {
            "id": "kw-20260603-verdict-history-gap",
            "title": "REJECT to FIX lifecycle is missing from structured findings",
            "type": "finding",
            "status": "active",
            "path": "entries/2026-06-03-verdict-history-gap.md",
            "tags": ["traceability", "compound-review", "sisyphus"]
        }
    ],
    "edges": [
        {
            "from": "kw-20260603-verdict-history-gap",
            "to": "kw-20260603-sisyphus-wiki-proposal",
            "type": "motivates"
        }
    ]
}
```

## graph.jsonl

`graph.jsonl` is the append-only event stream for graph mutations.

```jsonl
{"ts":"2026-06-03T00:00:00+09:00","event":"node.created","id":"kw-20260603-verdict-history-gap","path":"entries/2026/06/03/verdict-history-gap.md"}
{"ts":"2026-06-03T00:00:01+09:00","event":"edge.created","from":"kw-20260603-verdict-history-gap","to":"kw-20260603-sisyphus-wiki-proposal","type":"motivates"}
```

## Session ledger

`sessions/<session-id>.jsonl` stores distilled turn-level ledger records only. It is not a raw transcript and must link back to the canonical session store by `session_id`, `message_id`, and optional `part_id`.

```jsonl
{"ts":"2026-06-03T00:00:00+09:00","event":"turn.user","session_id":"ses_example","message_id":"msg_1","role":"user","text":"User requested graph-like LLM Wiki.","text_hash":"...","capture":"candidate"}
{"ts":"2026-06-03T00:00:01+09:00","event":"turn.assistant","session_id":"ses_example","message_id":"msg_2","role":"assistant","text":"Recommended distilled knowledge entries instead of raw event logs.","text_hash":"...","capture":"candidate"}
{"ts":"2026-06-03T00:00:02+09:00","event":"turn.tool","session_id":"ses_example","message_id":"msg_2","tool":"read","status":"completed","input":{"filePath":"..."},"output_preview":"...","capture":"observed"}
```

Allowed session-ledger events are `turn.session`, `turn.user`, `turn.assistant`, `turn.tool`, and `turn.todo`. Skip token deltas, TUI toasts, file watcher events, hidden reasoning, and events without a concrete session ID. Durable knowledge still belongs in `entries/`.
