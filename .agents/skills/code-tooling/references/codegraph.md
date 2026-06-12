# CodeGraph — Semantic Code Intelligence

CodeGraph provides symbol-level code understanding: definitions, references, call graphs, and impact analysis. It indexes the entire project into `.codegraph/` for fast queries.

## When to Use

- Find where a symbol (function, type, variable) is defined
- Find all callers or callees of a function
- Trace the call path from entry point to target
- Analyze what breaks if a symbol changes
- Explore module/package structure
- Get full context about a feature in one call

## Prerequisite: Index Health

Before any CodeGraph query, check index state:

```yaml
codegraph_status()
```

If the index is stale or missing after file changes, trigger re-index by running any codegraph query on changed files. The index auto-creates on first use.

## Cross-Project Queries

All CodeGraph tools accept an optional `projectPath` parameter to query a different project that has `.codegraph/` initialized:

```yaml
# Query a different project
codegraph_search(query: "AuthReducer", projectPath: "/path/to/other/project")
codegraph_node(symbol: "AuthReducer", includeCode: true, projectPath: "/path/to/other/project")
```

Omit `projectPath` to query the current project (default).

## MCP Tools

### Search & Locate

```yaml
# Search symbols by name (returns locations only)
codegraph_search(query: "FileManagerReducer")

# Search with kind filter
codegraph_search(query: "auth", kind: "function")  # function, method, class, interface, type, variable

# Search across files
codegraph_files(path: "apps/macos/Packages")       # list files under path
codegraph_files(pattern: "**/*.swift")              # glob pattern
```

### Get Definition & Source

```yaml
# Get symbol details + source code
codegraph_node(symbol: "FileManagerReducer", includeCode: true)

# Get symbol details without source (signature only)
codegraph_node(symbol: "FileManagerReducer", includeCode: false)
```

### References & Call Graph

```yaml
# Who calls this function? (all callers)
codegraph_callers(symbol: "FileManagerReducer", limit: 20)

# What does this function call? (all callees)
codegraph_callees(symbol: "FileManagerReducer", limit: 20)

# Trace call path from A to B
codegraph_trace(from: "AppReducer", to: "FileManagerReducer")
```

### Impact Analysis

```yaml
# What breaks if I change this symbol?
codegraph_impact(symbol: "FileManagerReducer", depth: 2)

# Higher depth = broader impact surface
codegraph_impact(symbol: "FileManagerReducer", depth: 3)
```

### Context & Exploration

```yaml
# Get full context about a task in one call (recommended for complex queries)
codegraph_context(task: "How does file search work in Voyager?", includeCode: true, maxNodes: 20)

# Control result size with maxNodes (default: 20)
codegraph_context(task: "Quick overview of X", maxNodes: 10)

# Explore multiple related symbols grouped by file
codegraph_explore(query: "FileManagerReducer SearchReducer FileIndex", maxFiles: 12)
```

## Workflow Patterns

### Pattern: Understand a feature

```yaml
1. codegraph_context(task: "Explain feature X")
2. codegraph_node(symbol: "keySymbol", includeCode: true)  # drill into key definition
3. codegraph_callers(symbol: "keySymbol")                   # who uses it
```

### Pattern: Assess change impact

```yaml
1. codegraph_impact(symbol: "symbolToChange", depth: 2)
2. codegraph_callers(symbol: "symbolToChange")              # direct callers
3. codegraph_trace(from: "AppReducer", to: "symbolToChange") # how it's reached
```

### Pattern: Find implementation of a concept

```yaml
1. codegraph_search(query: "search")
2. codegraph_context(task: "How is search implemented?")
3. codegraph_explore(query: "SearchReducer SearchView SearchClient")
```

## Limitations

- Dynamic dispatch (protocols with multiple conformances) may show incomplete call graphs
- CodeGraph index can become stale after large refactors — re-check with `codegraph_status`
- Very large codebases may need `limit` parameter to cap results

## Relationship to Other Tools

- Use **ast-grep** when CodeGraph can't find a pattern (e.g., TCA reducer composition, string literals)
- Use **XcodeBuildMCP** to verify CodeGraph findings compile correctly
- See `codegraph-usage` skill for Voyager-specific examples and deeper guides
