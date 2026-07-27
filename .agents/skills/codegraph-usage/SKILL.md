---
name: codegraph-usage
description: Routes CodeGraph exploration through OMO's single codegraph_explore MCP tool. Use for definitions, callers, callees, call paths, impact analysis, module structure, or cross-project source context.
---

# CodeGraph Usage

## Instructions

1. Put the symbol, file, or flow endpoints in one `codegraph_explore` query.
2. Use natural language when the question is about callers, impact, or architecture.
3. Treat returned line-numbered source as already read.
4. Follow the tool's staleness or missing-index guidance exactly.

```yaml
# Definition and source
codegraph_explore(query: "ComposerSaveReducer")

# Caller and impact analysis
codegraph_explore(query: "Who calls ComposerSaveReducer and what depends on it?")

# End-to-end flow
codegraph_explore(query: "SearchGateway search_router call path")

# Cross-project context
codegraph_explore(query: "AuthReducer", projectPath: "/path/to/project")
```

## Rules

- CodeGraph is the first read-equivalent call for indexed source.
- Do not call removed `codegraph_status`, `codegraph_search`, `codegraph_node`, `codegraph_callers`, `codegraph_trace`, or `codegraph_impact` tools.
- Do not re-read files already returned by `codegraph_explore` unless its staleness banner names them.
- For a flow question, name both endpoints in one query.
- Use the OMO `ast-grep` skill for syntax-shaped patterns and codemods.
- Use compiler, test, or LSP evidence to verify correctness after analysis.

See `references/explore.md` for query design and failure handling.

## Related skill

- `code-tooling` owns the broader selection among CodeGraph, ast-grep, LSP, repository build/test tasks, and Periphery.
