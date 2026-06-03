# codegraph_explore

Broad exploration of related code for a query. Returns relationships, source code, and file listings in a single response.

## Parameters

| Name          | Type   | Required | Default         | Constraints                                              |
| ------------- | ------ | -------- | --------------- | -------------------------------------------------------- |
| `query`       | string | **Yes**  | —               | Symbol/file/code terms to explore (NOT natural language) |
| `maxFiles`    | number | No       | adaptive        | Clamped to 1–20; default adapts to project size          |
| `projectPath` | string | No       | current project | Path to an initialized CodeGraph project                 |

## Return Shape

````
## Exploration: query

### Relationships
- SymbolA → SymbolB (calls)
- SymbolC ← SymbolD (called by)

### Source Code
#### filePath (N symbols)
```source code with line numbers```

### Files not shown above:
- filePath (language, N symbols)

### Budget note
Showing N of M relevant files.
````

## Behavior

- The **broadest exploration tool** — combines relationship mapping, source code, and file listing.
- Adapts output budget based on the total number of indexed files in the project.
- Can include flow chains from named symbols, relationship maps, verbatim source blocks, and file lists.
- Query should contain symbol names, file names, or code terms — **NOT natural language questions**.
- Source is verbatim current disk content with line numbers (unless `CODEGRAPH_EXPLORE_LINENUMS=0`).

## Edge Cases

- **No relevant code**: Returns `No relevant code found for "..."`.
- **Output truncated**: Adaptive cap based on project size. Budget note shows how much was omitted.
- **Natural language queries**: May return poor results — use concrete terms like symbol names or file paths.
- **Large projects**: Budget is more conservative. Use `maxFiles` to control.

## Voyager Examples

Explore the Composer feature:

```
codegraph_explore(query: "ComposerSave composer save")
```

Explore the search backend:

```
codegraph_explore(query: "search_router collection_search")
```

Explore XPC service boundaries:

```
codegraph_explore(query: "FilterSearchXPC helper search")
```

## Tips

- Use when you need a **broad overview** — it's like a smart `grep` that returns structured context.
- For specific questions ("who calls this?"), use `codegraph_callers` or `codegraph_trace` instead.
- For understanding a new module, combine with `codegraph_context` for the "why" and `codegraph_explore` for the "what".
- Keep queries concrete — "ComposerSave reducer" works better than "how does saving work?".
