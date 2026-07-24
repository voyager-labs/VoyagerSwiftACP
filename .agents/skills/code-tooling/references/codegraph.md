# CodeGraph — OMO Semantic Code Intelligence

OMO exposes CodeGraph through one MCP tool: `codegraph_explore`. It returns current, line-numbered source grouped by file together with call paths and blast-radius information.

## Use it for

- Definitions and source for named symbols
- Callers, callees, and multi-hop call paths
- Change-impact analysis
- Feature and module exploration
- Cross-project queries when another project is indexed

## Tool shape

```yaml
codegraph_explore(
  query: "FileManagerReducer callers impact",
  maxFiles: 12,
  projectPath: "/optional/other/project"
)
```

- `query` accepts natural language, symbol names, file names, or endpoints of a flow.
- `maxFiles` caps returned source files.
- `projectPath` selects another indexed project. Omit it for the current workspace.

## Query patterns

```yaml
# Definition and source
codegraph_explore(query: "FileManagerReducer")

# Callers and impact
codegraph_explore(query: "Who calls FileManagerReducer and what depends on it?")

# Call path
codegraph_explore(query: "AppReducer FileManagerReducer call path")

# Module context
codegraph_explore(query: "FileManagerReducer SearchClient FileIndex")
```

## Operating rules

1. Call CodeGraph before reading indexed code manually.
2. Treat returned source as already read; do not reopen the same files.
3. Name both endpoints for flow questions instead of reconstructing a path with grep.
4. Follow any staleness banner. Read only files explicitly reported as pending re-index.
5. If CodeGraph reports that the project is not indexed, stop calling it for that project and use local tools. Do not initialize the index on the user's behalf.

## Boundaries

- Use the OMO `ast-grep` skill for structural syntax patterns and codemods.
- Use LSP rename for semantic renames.
- Use repository verification commands to prove compilation and tests.
- CodeGraph supplements compiler evidence; it does not replace it.
