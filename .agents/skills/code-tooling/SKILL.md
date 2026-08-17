---
name: code-tooling
description: Routing guide for development tooling. Maps code tasks to the right tool — CodeGraph for symbol intelligence, ast-grep for AST search and rewrite, repository tasks and SwiftPM commands for build/test verification, and Periphery for unused code detection. Use when the agent needs to find definitions, search references, trace call graphs, analyze change impact, search or rewrite code patterns, check compile errors, run tests, detect unused code, or navigate code structure. Triggers on: find definition, find references, callers, callees, call graph, impact analysis, code search, pattern search, code rewrite, rename, diagnostics, compile errors, build, test, unused code, code structure, symbol lookup.
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

| Task                       | Primary tool                      | Secondary tool            | Reference                                                                |
| -------------------------- | --------------------------------- | ------------------------- | ------------------------------------------------------------------------ |
| Find a symbol's definition | **CodeGraph** `codegraph_explore` | OMO `ast-grep` skill      | [codegraph](references/codegraph.md), [ast-grep](references/ast-grep.md) |
| Find who calls a function  | **CodeGraph** `codegraph_explore` | —                         | [codegraph](references/codegraph.md)                                     |
| Find what a function calls | **CodeGraph** `codegraph_explore` | —                         | [codegraph](references/codegraph.md)                                     |
| Trace call path A → B      | **CodeGraph** `codegraph_explore` | —                         | [codegraph](references/codegraph.md)                                     |
| Analyze change impact      | **CodeGraph** `codegraph_explore` | —                         | [codegraph](references/codegraph.md)                                     |
| Get feature context        | **CodeGraph** `codegraph_explore` | —                         | [codegraph](references/codegraph.md)                                     |
| Explore module structure   | **CodeGraph** `codegraph_explore` | —                         | [codegraph](references/codegraph.md)                                     |
| Search by symbol name      | **CodeGraph** `codegraph_explore` | —                         | [codegraph](references/codegraph.md)                                     |
| Search code pattern (AST)  | OMO **ast-grep skill** + `sg`     | —                         | [ast-grep](references/ast-grep.md)                                       |
| Rewrite code pattern (AST) | OMO **ast-grep skill** + `sg`     | —                         | [ast-grep](references/ast-grep.md)                                       |
| Rename across codebase     | **LSP rename**                    | ast-grep codemod          | [ast-grep](references/ast-grep.md)                                       |
| macOS/package verification | Capability matrix below           | Existing repository route | [package-integration](references/package-integration.md)                 |
| Simulator compile/test/run | Repository-defined task only      | —                         | Capability matrix below                                                  |
| Detect unused code         | **Periphery** CLI                 | —                         | [periphery](references/periphery.md)                                     |

## Decision Flowchart

```
What do you need to do?

"Where is X defined?"
  → CodeGraph codegraph_explore(query: "X")
  → Fallback: load the ast-grep skill and run a structural search

"Who calls this function?"
  → CodeGraph codegraph_explore(query: "Who calls FunctionName?")

"How does A reach B?"
  → CodeGraph codegraph_explore(query: "A B call path")

"What breaks if I change X?"
  → CodeGraph codegraph_explore(query: "impact of changing X")

"Find all code matching pattern P"
  → Load the OMO ast-grep skill
  → Use its helper or `sg run -p 'P' --lang swift`

"Replace all X with Y"
  → Load the OMO ast-grep skill and dry-run its helper/`sg` rewrite first
  → Then select the matching verifier from the capability matrix

"Verify macOS scheme or SwiftPM package"
  → Capability matrix → repository mise task or xcrun swift command

"Verify simulator compile/test/run"
  → Use a repository-defined task when one exists; otherwise stop and report the missing executor

"Find unused code"
  → Periphery CLI (mise exec -- periphery scan)

"How is this feature organized?"
  → CodeGraph codegraph_explore(query: "...")

"Rename a symbol across codebase"
  → LSP prepare_rename → rename for semantic renames
  → ast-grep codemod only for syntax-shaped migrations
```

## Instructions

### 1. Start symbol-level work with CodeGraph

Call `codegraph_explore` directly. OMO bootstraps and syncs the index on session start. Follow any staleness banner in the tool response; do not call removed status/init tools.

### 2. CodeGraph is the primary tool for symbol-level work

For definitions, references, call graphs, and impact analysis — start with CodeGraph. It provides semantic understanding that text-based tools cannot.

Load `references/codegraph.md` for detailed tool parameters and workflow patterns.

### 3. ast-grep is for pattern-level work

When you need to find or rewrite structural code patterns (TCA composition, API migration, convention checks) — use ast-grep. It understands AST structure, not just text.

Load `references/ast-grep.md` for pattern syntax, examples, and custom rules.

### 4. Capability-based build and test executor selection

This matrix owns executor selection and applies to interactive agents, while repository `mise` tasks remain valid human and CI paths.

#### UI automation guardrail

- Do not run unsolicited `osascript`, AppleScript, or equivalent UI-click automation during verification.
- Prefer source inspection, focused tests, repository builds, runtime logs, and process state.
- Use UI automation only when the user explicitly requests an interaction flow or manual UI verification; otherwise report that visual interaction was not automated.

#### Verification proportionality

- Match verification depth to the change: use the smallest relevant check for a narrow edit, and expand to broader tests only when the change crosses module or runtime boundaries.
- For genuinely presentation-only edits—such as spacing, color, typography, control sizing, or visual alignment changes with no state, action, API, package, or interaction-semantic change—do not spend time on full test suites, full-app builds, or broad runtime QA by default. Prefer a targeted lint/format check or no automated check when the edit is self-evident; run compile or surface verification only when the user requests it or the change can affect behavior.
- Do not repeat full build, full test, lint, and diff checks after every intermediate edit when a focused check provides sufficient evidence.
- Treat Oracle as an escalation path for architecture decisions, hard debugging, repeated verification failure, security/performance risk, or significant post-implementation review—not as a default step for every request.

| Required outcome                                      | Preferred executor                                              | Supported scope                                                              | Existing fallback                                                                       | Stop condition                                                                        |
| ----------------------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Package-local build or focused package tests          | `xcrun swift build` / `xcrun swift test --package-path <path>`  | Local SwiftPM package compilation and tests                                  | Unfiltered `xcrun swift test` for the same package when a focused filter is unavailable | Package path, toolchain, or test suite cannot be identified                           |
| Simulator project build, focused/full test, or launch | Repository-defined task when one exists                         | Scope explicitly owned by that task                                          | Stop and report the missing executor                                                    | No repository task proves the requested simulator scope                               |
| macOS scheme build                                    | `mise run macos-build`                                          | Voyager macOS development scheme                                             | Stop if the repository task cannot run in the current environment                       | The repository task is unavailable or cannot prove the required scheme                |
| macOS scheme focused test                             | `mise run macos-test-flow -- --flow <flow-id>` for mapped flows | Canonical mapped flow suite                                                  | `mise run macos-test` as a recorded broader fallback                                    | Neither route can prove the intended behavior                                         |
| macOS scheme full test                                | `mise run macos-test`                                           | Voyager macOS development scheme; inspect its result/log for target coverage | Stop if the repository task cannot run in the current environment                       | The repository task is unavailable or cannot prove intended targets                   |
| Swift lint or format                                  | `mise exec -- swiftlint ...` / `mise exec -- swiftformat ...`   | Touched macOS Swift sources                                                  | Stop when the pinned repository tool is unavailable                                     | Style result cannot be produced by the repository toolchain                           |
| Physical-device build, test, install, or launch       | No preferred executor in the current tool surface               | None: device operations are not exposed here                                 | Stop and report the missing device capability                                           | Never invent a device MCP operation or substitute an unrelated simulator/macOS result |

Load `references/package-integration.md` for local SwiftPM product, target, dependency, and consumer wiring verification. Load `references/swift6-package-rules.md` when creating packages, adding or moving types into packages, editing `Package.swift`, or fixing Sendable errors.
Load `references/voyager-verification.md` for focused Voyager verification, SwiftFormat path resolution, and callback/async proof requirements.

### 5. Periphery for dead code scans

Periodic unused code detection. CLI tool, not an MCP.

Load `references/periphery.md` for scan commands and configuration.

### 6. Parallelize independent calls

If you need unrelated CodeGraph questions, include their symbols and flow endpoints in one `codegraph_explore` query. Run independent `sg` searches in parallel when their patterns do not depend on each other.

## Common Mistakes

- **Reading entire files to find a definition** — use `codegraph_explore` instead
- **Using text grep for code patterns** — load the ast-grep skill and use `sg` for AST-aware matching
- **Bypassing repository tasks with raw `xcodebuild`** — select the canonical executor from the capability matrix
- **Calling removed CodeGraph status/search/node tools** — OMO exposes one `codegraph_explore` tool
- **Sequential calls when parallel is possible** — independent queries should run simultaneously

## Reading References

Do NOT read all reference files at once. Load only what the current task needs:

| Task type                    | Read                                            | Skip                      |
| ---------------------------- | ----------------------------------------------- | ------------------------- |
| Find definition / references | `codegraph.md`                                  | All others                |
| Search or rewrite patterns   | `ast-grep.md`                                   | All others                |
| Build / test / compile check | Capability matrix and `voyager-verification.md` | Unrelated tool references |
| SwiftPM package integration  | `references/package-integration.md`             | Unrelated tool references |
| Swift 6 package rules        | `references/swift6-package-rules.md`            | Unrelated tool references |
| Unused code scan             | `periphery.md`                                  | All others                |
| Multiple concerns            | Load only the files for tools you'll use        | Others                    |

## Related Skills

| Skill             | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `codegraph-usage` | Deep CodeGraph guides with Voyager-specific examples |
| `voyager-dev`     | Voyager macOS TCA + FSD orchestrator                 |
