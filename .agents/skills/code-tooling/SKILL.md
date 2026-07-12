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
| Simulator compile/test/run | **XcodeBuildMCP** when supported  | Explicit matrix fallback   | [xcodebuild-mcp](references/xcodebuild-mcp.md)                           |
| macOS/package verification | Capability matrix below           | Existing repository route  | [xcodebuild-mcp](references/xcodebuild-mcp.md)                           |
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

"Verify simulator compile/test/run"
  → Capability matrix → session_show_defaults → supported XcodeBuildMCP operation

"Verify macOS scheme or SwiftPM package"
  → Capability matrix → repository mise task or xcrun swift command

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

### 4. Capability-based build and test executor selection

This matrix owns executor selection and applies to interactive agents, while repository `mise` tasks remain valid human and CI paths.

| Required outcome                                      | Preferred executor                                                                      | Supported scope                                                              | Existing fallback                                                                                  | Stop condition                                                                                                       |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Package-local build or focused package tests          | `xcrun swift build` / `xcrun swift test --package-path <path>`                          | Local SwiftPM package compilation and tests                                  | Unfiltered `xcrun swift test` for the same package when a focused filter is unavailable            | Package path, toolchain, or test suite cannot be identified                                                          |
| Simulator project build, focused/full test, or launch | XcodeBuildMCP `build_sim`, `test_sim`, or `build_run_sim` after `session_show_defaults` | Exposed iOS-simulator project/scheme/defaults only                           | Stop; this repository has no verified simulator-specific repository task                           | MCP tool, defaults, simulator, or requested simulator scope is unavailable                                           |
| macOS scheme build                                    | `mise run macos-build`                                                                  | Voyager macOS development scheme                                             | Stop if the repository task cannot run in the current environment                                  | No macOS-capable MCP operation is exposed and the repository task is unavailable or cannot prove the required scheme |
| macOS scheme focused test                             | No focused macOS executor is exposed in the current tool surface                        | None                                                                         | `mise run macos-test` only after recording it as a broader fallback and inspecting target coverage | A focused result is required but the broader repository task cannot prove intended target coverage                   |
| macOS scheme full test                                | `mise run macos-test`                                                                   | Voyager macOS development scheme; inspect its result/log for target coverage | Stop if the repository task cannot run in the current environment                                  | No macOS-capable MCP operation is exposed and the repository task is unavailable or cannot prove intended targets    |
| Swift lint or format                                  | `mise exec -- swiftlint ...` / `mise exec -- swiftformat ...`                           | Touched macOS Swift sources                                                  | Stop when the pinned repository tool is unavailable                                                | Style result cannot be produced by the repository toolchain                                                          |
| Physical-device build, test, install, or launch       | No preferred executor in the current tool surface                                       | None: device operations are not exposed here                                 | Stop and report the missing device capability                                                      | Never invent a device MCP operation or substitute an unrelated simulator/macOS result                                |

Before the first available XcodeBuildMCP build, run, or test operation in a session, call `XcodeBuildMCP_session_show_defaults()`. Use an MCP operation only when both the operation and its required scope are exposed; do not call raw `xcodebuild` from an agent as a substitute for this matrix.

Load `references/xcodebuild-mcp.md` for session setup and the supported simulator operations. Load `references/package-integration.md` for local SwiftPM product, target, dependency, and consumer wiring verification. Load `references/swift6-package-rules.md` when creating packages, adding or moving types into packages, editing `Package.swift`, or fixing Sendable errors.

### 5. Periphery for dead code scans

Periodic unused code detection. CLI tool, not an MCP.

Load `references/periphery.md` for scan commands and configuration.

### 6. Parallelize independent calls

If you need both definition AND references — call `codegraph_node` and `codegraph_callers` in parallel. If you need to search two different patterns — run both `ast_grep_search` calls at once.

## Common Mistakes

- **Reading entire files to find a definition** — use `codegraph_node` instead
- **Using text grep for code patterns** — use `ast_grep_search` for AST-aware matching
- **Treating XcodeBuildMCP as universal** — select the executor by operation and supported platform from the capability matrix
- **Running CodeGraph queries on a stale index** — check `codegraph_status` first
- **Sequential calls when parallel is possible** — independent queries should run simultaneously
- **Skipping session defaults before building** — always run `session_show_defaults` first

## Reading References

Do NOT read all reference files at once. Load only what the current task needs:

| Task type                    | Read                                      | Skip                      |
| ---------------------------- | ----------------------------------------- | ------------------------- |
| Find definition / references | `codegraph.md`                            | All others                |
| Search or rewrite patterns   | `ast-grep.md`                             | All others                |
| Build / test / compile check | `xcodebuild-mcp.md` and capability matrix | All others                |
| SwiftPM package integration  | `package-integration.md`                  | Unrelated tool references |
| Swift 6 package rules        | `swift6-package-rules.md`                 | Unrelated tool references |
| Unused code scan             | `periphery.md`                            | All others                |
| Multiple concerns            | Load only the files for tools you'll use  | Others                    |

## Related Skills

| Skill             | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `codegraph-usage` | Deep CodeGraph guides with Voyager-specific examples |
| `voyager-dev`     | Voyager macOS TCA + FSD orchestrator                 |
