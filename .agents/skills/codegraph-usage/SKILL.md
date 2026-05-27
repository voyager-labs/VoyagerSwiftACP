---
name: codegraph-usage
description: Guides effective use of the CodeGraph MCP sidecar for call flow tracing, impact analysis, symbol exploration, and cross-language queries. Use when needing to answer "who calls this?", "call path from A to B", "impact of changing this symbol", or exploring module/package structure. Prefer over grep+read for call chain and dependency questions.
compatibility: opencode
---

# CodeGraph Usage

## When to use this skill

- You need to trace call chains ("who calls this reducer?", "call path from A to B")
- You need impact analysis for a symbol change ("what breaks if I change this?")
- You need to explore module/package structure without reading files
- You need cross-language tracing (Swift ↔ Python)
- You need to find all callers/callees of a function, type, or endpoint
- `.codegraph/` index exists (check with `just codegraph-status`)

## MCP Tools Reference

See `references/` directory for deep-dive usage guides per tool.

| Tool                | Purpose                                          | Reference file             |
| ------------------- | ------------------------------------------------ | -------------------------- |
| `codegraph_search`  | Search symbols / file names                      | `references/01-search.md`  |
| `codegraph_context` | Return surrounding context for a specific symbol | `references/02-context.md` |
| `codegraph_trace`   | Trace call path from A to B                      | `references/03-trace.md`   |
| `codegraph_callers` | Find all callers of a specific symbol            | `references/04-callers.md` |
| `codegraph_callees` | Find all targets called by a specific symbol     | `references/05-callees.md` |
| `codegraph_impact`  | Analyze impact scope of a symbol change          | `references/06-impact.md`  |
| `codegraph_explore` | Explore module / package structure               | `references/07-explore.md` |
| `codegraph_node`    | Get detailed info for a specific node            | `references/08-node.md`    |
| `codegraph_files`   | List indexed files                               | `references/09-files.md`   |
| `codegraph_status`  | Check index status                               | `references/10-status.md`  |

## Prerequisites

- `.codegraph/` index must exist in the project root.
- If missing, run `just codegraph-init` or it auto-initializes on `git checkout`/`git worktree add`.
- Check status: `just codegraph-status`
- Rebuild if stale: `just codegraph-reindex`

## Additional References

| Topic                           | File                                |
| ------------------------------- | ----------------------------------- |
| Query patterns & workflows      | `references/11-patterns.md`         |
| Voyager-specific examples       | `references/12-voyager-examples.md` |
| Limitations & gotchas           | `references/13-limitations.md`      |
| Evaluation framework (Go/No-Go) | `references/14-evaluation.md`       |

## Removal Procedure

1. `just codegraph-clean` — delete index
2. Remove codegraph MCP entry from `opencode.json`
3. Remove codegraph commands from `justfile`
4. Remove `lefthook.yml` codegraph entry from post-checkout
5. Delete this skill directory
