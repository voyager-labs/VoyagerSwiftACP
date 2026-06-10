---
name: code-tooling
description: Routing guide for development tooling. Maps code tasks to the right tool — CodeGraph for symbol intelligence, ast-grep for AST search and rewrite, XcodeBuildMCP for build/test/diagnostics, Periphery for unused code detection. Use when the agent needs to find definitions, search references, trace call graphs, analyze change impact, search or rewrite code patterns, check compile errors, run tests, detect unused code, or navigate code structure. Triggers on: find definition, find references, callers, callees, call graph, impact analysis, code search, pattern search, code rewrite, rename, diagnostics, compile errors, build, test, unused code, code structure, symbol lookup.
---

# Code Tooling Routing Guide

## When to Use This Skill

Load this skill when the task involves any of these operations:

| Operation              | What you need to do                                       |
| ---------------------- | --------------------------------------------------------- |
| Find a definition      | "Where is X defined?", "Show me the source of Y"          |
| Find references        | "Who calls this?", "Where is this used?"                  |
| Trace call flow        | "How does A reach B?", "Trace the call path"              |
| Analyze impact         | "What breaks if I change X?"                              |
| Search code patterns   | "Find all functions that...", "Find Reducer conformances" |
| Rewrite code patterns  | "Replace all X with Y", "Migrate API usage"               |
| Check compile errors   | "Does this compile?", "What are the errors?"              |
| Run tests              | "Run the tests", "Verify this works"                      |
| Find unused code       | "Dead code scan", "What's unused?"                        |
| Explore code structure | "How is this module organized?", "List symbols"           |

## Task → Tool Routing

| Task                       | Primary tool                      | Secondary tool             | Reference                                                                |
| -------------------------- | --------------------------------- | -------------------------- | ------------------------------------------------------------------------ |
| Find a symbol's definition | **CodeGraph** `codegraph_node`    | ast-grep `ast_grep_search` | [codegraph](references/codegraph.md), [ast-grep](references/ast-grep.md) |
| Find who calls a function  | **CodeGraph** `codegraph_callers` | —                          | [codegraph](references/codegraph.md)                                     |
| Find what a function calls | **CodeGraph** `codegraph_callees` | —                          | [codegraph](references/codegraph.md)                                     |
| Trace call path A → B      | **CodeGraph** `codegraph_trace`   | —                          | [codegraph](references/codegraph.md)                                     |
| Analyze change impact      | **CodeGraph** `codegraph_impact`  | —                          | [codegraph](references/codegraph.md)                                     |
| Get feature context        | **CodeGraph** `codegraph_context` | —                          | [codegraph](references/codegraph.md)                                     |
| Explore module structure   | **CodeGraph** `codegraph_explore` | `codegraph_files`          | [codegraph](references/codegraph.md)                                     |
| Search by symbol name      | **CodeGraph** `codegraph_search`  | —                          | [codegraph](references/codegraph.md)                                     |
| Search code pattern (AST)  | **ast-grep** `ast_grep_search`    | —                          | [02-ast-grep](references/ast-grep.md)                                    |
| Rewrite code pattern (AST) | **ast-grep** `ast_grep_replace`   | —                          | [02-ast-grep](references/ast-grep.md)                                    |
| Rename across codebase     | **ast-grep** `ast_grep_replace`   | manual `edit` (replaceAll) | [02-ast-grep](references/ast-grep.md)                                    |
| Check compile errors       | **XcodeBuildMCP** `build_sim`     | —                          | [xcodebuild-mcp](references/xcodebuild-mcp.md)                           |
| Run tests                  | **XcodeBuildMCP** `test_sim`      | —                          | [xcodebuild-mcp](references/xcodebuild-mcp.md)                           |
| Build and run app          | **XcodeBuildMCP** `build_run_sim` | —                          | [xcodebuild-mcp](references/xcodebuild-mcp.md)                           |
| Take UI snapshot           | **XcodeBuildMCP** `snapshot_ui`   | —                          | [xcodebuild-mcp](references/xcodebuild-mcp.md)                           |
| Detect unused code         | **Periphery** CLI                 | —                          | [periphery](references/periphery.md)                                     |

## Decision Flowchart

```
What do you need to do?

"Where is X defined?"
  → CodeGraph codegraph_search → codegraph_node(includeCode: true)
  → Fallback: ast-grep ast_grep_search

"Who calls this function?"
  → CodeGraph codegraph_callers

"How does A reach B?"
  → CodeGraph codegraph_trace(from: "A", to: "B")

"What breaks if I change X?"
  → CodeGraph codegraph_impact(symbol: "X", depth: 2)

"Find all code matching pattern P"
  → ast-grep ast_grep_search(pattern: "P", lang: "swift")

"Replace all X with Y"
  → ast-grep ast_grep_replace (dry-run first)
  → Then XcodeBuildMCP build_sim to verify

"Does this compile?" / "What are the errors?"
  → XcodeBuildMCP session_show_defaults → build_sim

"Run the tests"
  → XcodeBuildMCP session_show_defaults → test_sim

"Find unused code"
  → Periphery CLI (mise exec -- periphery scan)

"How is this feature organized?"
  → CodeGraph codegraph_context(task: "...")
  → CodeGraph codegraph_explore(query: "...")

"Rename a symbol across codebase"
  → ast-grep ast_grep_replace (for AST-aware rename)
  → manual edit with replaceAll (for simple text rename)
```

## Instructions

### 1. Always check CodeGraph index first

```yaml
codegraph_status()
```

A stale index gives inaccurate results. If files changed significantly, trigger a re-index by running any codegraph query.

### 2. CodeGraph is the primary tool for symbol-level work

For definitions, references, call graphs, and impact analysis — start with CodeGraph. It provides semantic understanding that text-based tools cannot.

Load `references/codegraph.md` for detailed tool parameters and workflow patterns.

### 3. ast-grep is for pattern-level work

When you need to find or rewrite structural code patterns (TCA composition, API migration, convention checks) — use ast-grep. It understands AST structure, not just text.

Load `references/ast-grep.md` for pattern syntax, examples, and custom rules.

### 4. XcodeBuildMCP is the only build/test tool

All build and test operations go through XcodeBuildMCP. Never call `xcodebuild` directly.

Load `references/xcodebuild-mcp.md` for session setup, build/test commands, and simulator management.

### 5. Periphery for dead code scans

Periodic unused code detection. CLI tool, not an MCP.

Load `references/periphery.md` for scan commands and configuration.

### 6. Parallelize independent calls

If you need both definition AND references — call `codegraph_node` and `codegraph_callers` in parallel. If you need to search two different patterns — run both `ast_grep_search` calls at once.

## Common Mistakes

- **Reading entire files to find a definition** — use `codegraph_node` instead
- **Using text grep for code patterns** — use `ast_grep_search` for AST-aware matching
- **Calling xcodebuild directly** — use XcodeBuildMCP for all build/test operations
- **Running CodeGraph queries on a stale index** — check `codegraph_status` first
- **Sequential calls when parallel is possible** — independent queries should run simultaneously
- **Skipping session defaults before building** — always run `session_show_defaults` first

## Reading References

Do NOT read all reference files at once. Load only what the current task needs:

| Task type                    | Read                                     | Skip       |
| ---------------------------- | ---------------------------------------- | ---------- |
| Find definition / references | `codegraph.md`                           | All others |
| Search or rewrite patterns   | `ast-grep.md`                            | All others |
| Build / test / compile check | `xcodebuild-mcp.md`                      | All others |
| Unused code scan             | `periphery.md`                           | All others |
| Multiple concerns            | Load only the files for tools you'll use | Others     |

## Related Skills

| Skill             | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `codegraph-usage` | Deep CodeGraph guides with Voyager-specific examples |
| `voyager-dev`     | Voyager macOS TCA + FSD orchestrator                 |
| `verification`    | Build/test verification gates                        |
