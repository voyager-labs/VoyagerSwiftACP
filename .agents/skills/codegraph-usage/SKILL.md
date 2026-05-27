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
- SourceKit-LSP find-references is too slow or does not cover the scope needed

## When NOT to use this skill

- Go to definition / find references → use SourceKit-LSP instead
- Code completion → use SourceKit-LSP instead
- Exact Swift type inference needed → SourceKit-LSP (compiler-level) is more accurate
- CodeGraph MCP server is not running or `.codegraph/` index does not exist

## SourceKit-LSP vs CodeGraph decision table

| Scenario                           | SourceKit-LSP         | CodeGraph             |
| ---------------------------------- | --------------------- | --------------------- |
| Go to definition / Find references | O (in editor)         | X                     |
| Code completion                    | O                     | X                     |
| "Who calls this function?"         | Slow (editor session) | O (callers)           |
| "Call path from A to B"            | Not available         | O (trace)             |
| "Impact scope of this change"      | Limited               | O (impact)            |
| "What is this module's structure?" | Not available         | O (explore/context)   |
| FastAPI route recognition          | X                     | O                     |
| Swift type accuracy                | O (compiler-level)    | ~ (tree-sitter-level) |

## MCP Tools Reference

| Tool                | Purpose                                          | When to use                         |
| ------------------- | ------------------------------------------------ | ----------------------------------- |
| `codegraph_search`  | Search symbols / file names                      | "Find files/symbols matching X"     |
| `codegraph_context` | Return surrounding context for a specific symbol | "Show me what's around this symbol" |
| `codegraph_trace`   | Trace call path from A to B                      | "How does A reach B?"               |
| `codegraph_callers` | Find all callers of a specific symbol            | "Who calls this function/reducer?"  |
| `codegraph_callees` | Find all targets called by a specific symbol     | "What does this function call?"     |
| `codegraph_impact`  | Analyze impact scope of a symbol change          | "What breaks if I change this?"     |
| `codegraph_explore` | Explore module / package structure               | "What's in this package?"           |
| `codegraph_node`    | Get detailed info for a specific node            | "Tell me more about this symbol"    |
| `codegraph_files`   | List indexed files                               | "What files are in the index?"      |
| `codegraph_status`  | Check index status                               | "Is the index up to date?"          |

## Instructions

### Pattern 1: Find who calls a symbol

Use `codegraph_callers` when you need to find all call sites.

```
codegraph_callers("ComposerSaveReducer.Action")
```

- Returns a list of all locations that call the given symbol.
- More complete than grep because it handles indirect calls (protocols, closures).
- Use for: "Where is this action dispatched?", "Who creates this dependency?"

### Pattern 2: Trace a call path from A to B

Use `codegraph_trace` when you need to understand how code flows from one point to another.

```
codegraph_trace("SearchGateway", "search_router")
```

- Returns the full call chain between two symbols.
- Works across languages (Swift → Python).
- Use for: "How does the frontend reach this API?", "What's the handler chain?"

### Pattern 3: Impact analysis

Use `codegraph_impact` before changing a shared symbol.

```
codegraph_impact("VoyagerFeaturesComposer")
```

- Returns all symbols that depend on the given symbol.
- More accurate than file-path-based tools because it traces symbol dependencies.
- Use before: refactoring, API changes, moving files.

### Pattern 4: Explore module structure

Use `codegraph_explore` + `codegraph_context` when onboarding to a new module.

```
codegraph_explore  // list packages/modules
codegraph_context("VoyagerFeaturesComposer")  // see what's inside
```

- Faster than reading 5-10 files to understand structure.
- Use for: "What's in this package?", "How is this module organized?"

### Pattern 5: Cross-language tracing

Use `codegraph_trace` for Swift ↔ Python boundary questions.

```
codegraph_trace("SearchGateway", "search_router")
```

- Traces Swift API calls through to Python FastAPI endpoints.
- Use for: "Which backend endpoint does this frontend call hit?"

## Voyager-Specific Query Examples

### TCA Reducer Call Chain

"Where is this reducer's Action called from?"

```
codegraph_callers("ComposerSaveReducer.Action")
```

### FastAPI Route Tracing

"What is the handler chain for this endpoint?"

```
codegraph_trace("search_router", "collection_search")
```

### Package Dependency Analysis

"Which other packages use this package?"

```
codegraph_impact("VoyagerFeaturesComposer")
```

### Cross-Language Tracing

"Swift to Python backend API call path"

```
codegraph_trace("SearchGateway", "search_router")
```

## Prerequisites

- `.codegraph/` index must exist in the project root.
- If missing, run `just codegraph-init` or it auto-initializes on `git checkout`/`git worktree add`.
- Check status: `just codegraph-status`
- Rebuild if stale: `just codegraph-reindex`

## Limitations

- ObjC bridge headers have partial support.
- Files over 1MB are excluded from indexing.
- tree-sitter-based; compiler-level type inference not available (e.g., generic complexity).
- Swift macro attributes cannot be traced.
- Index auto-updates only while MCP server is running (via opencode). When offline, run `just codegraph-reindex` manually.

## Evaluation Framework (Go/No-Go)

CodeGraph adoption is measured across 7 angles. After 2 weeks, decide whether to retain.

### Evaluation Angles

1. **Exploration Speed** — 30%+ time reduction for understanding new modules
2. **Call Flow Accuracy** — 80%+ accuracy on known TCA reducer call paths
3. **Impact Analysis Coverage** — 0 misses vs macos_checks, under 20% over-inclusion
4. **Cross-Language Tracing** — 50%+ success on Swift↔Python boundary queries
5. **Agent Workflow Improvement** — 40%+ reduction in exploration tool calls
6. **Maintenance Cost** — cost must not exceed benefit
7. **Token Savings** — 50%+ token reduction for exploration tasks

### Go/No-Go Criteria

- **Go**: 4+ angles rated "Improved", maintenance cost acceptable, no conflicts with existing tools.
- **No-Go**: 3 or fewer "Improved", or maintenance exceeds benefit, or conflicts detected.

### Measurement Record Template

```
### [Angle Name] -- [Measurement Date]
- Before: [measured value]
- After: [measured value]
- Improvement rate: [X%]
- Verdict: [Improved / No change / Degraded]
- Notes: [additional observations]
```

### Removal Procedure

1. `just codegraph-clean` — delete index
2. Remove codegraph MCP entry from `opencode.json`
3. Remove codegraph commands from `justfile`
4. Remove `lefthook.yml` codegraph entry from post-checkout
5. Delete this skill directory
