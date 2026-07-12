---
name: codegraph-usage
description: Guides effective use of the CodeGraph MCP sidecar for call flow tracing, impact analysis, symbol exploration, and cross-language queries. Use when needing to answer "who calls this?", "call path from A to B", "impact of changing this symbol", or exploring module/package structure. Prefer over grep+read for call chain and dependency questions.
---

# CodeGraph Usage

## Quick Workflow

1. **Index ready?** `mise run codegraph-status`
2. **Find a symbol:** `codegraph_search` → see `references/01-search.md`
3. **Trace call flow:** `codegraph_trace` or `codegraph_callers` → see `references/11-patterns.md`
4. **Check impact:** `codegraph_impact` → see `references/11-patterns.md`

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

## Additional References

| Topic                           | File                                |
| ------------------------------- | ----------------------------------- |
| Query patterns & workflows      | `references/11-patterns.md`         |
| Voyager-specific examples       | `references/12-voyager-examples.md` |
| Limitations & gotchas           | `references/13-limitations.md`      |
| Evaluation framework (Go/No-Go) | `references/14-evaluation.md`       |
| Removal procedure               | `references/15-removal.md`          |

## Reading References

Do NOT read all reference files at once. Load only what the current task needs:

| Task type                   | Read these                            | Skip these            |
| --------------------------- | ------------------------------------- | --------------------- |
| "Find callers/callees"      | `04-callers.md` or `05-callees.md`    | All others            |
| "Trace A to B"              | `03-trace.md`                         | All others            |
| "What breaks if I change X" | `06-impact.md`                        | All others            |
| "Explore a module"          | `07-explore.md`, `02-context.md`      | All others            |
| "First time / onboarding"   | `11-patterns.md`, `13-limitations.md` | Tool-specific (01-10) |
| "Voyager-specific examples" | `12-voyager-examples.md`              | All others            |
| "Removing CodeGraph"        | `15-removal.md`                       | All others            |
| Need tool parameter details | Specific tool file (01-10)            | Others in 01-10       |

## Related Skills

| Skill          | Purpose                                              |
| -------------- | ---------------------------------------------------- |
| `code-tooling` | Routing guide for code navigation, search, and build |

## Prerequisites

- `.codegraph/` index must exist in the project root.
- If missing, run `mise run codegraph-init` or it auto-initializes on `git checkout`/`git worktree add`.
- Check status: `mise run codegraph-status`
- Rebuild if stale: `mise run codegraph-reindex`
