# codegraph_callees

Finds all symbols that a specific symbol calls. Answers "what does this function depend on?"

## Parameters

| Name          | Type   | Required | Default         | Constraints                              |
| ------------- | ------ | -------- | --------------- | ---------------------------------------- |
| `symbol`      | string | **Yes**  | —               | Symbol name to search for                |
| `limit`       | number | No       | 20              | Clamped to 1–100 at runtime              |
| `projectPath` | string | No       | current project | Path to an initialized CodeGraph project |

## Return Shape

```
## Callees of SymbolName (N found)

- CalleeName (kind) - filePath:line
- CalleeName (kind) - filePath:line
...
```

If symbol not found: `Symbol "..." not found in the graph...`
If no callees: `No callees found for "..." — this symbol may not call other indexed code.`

## Behavior

- Symmetric to `codegraph_callers` — but returns outgoing calls instead of incoming.
- Searches for all symbols matching the given name, then collects their callees.
- Aggregates results across all matches.

## Edge Cases

- **No callees**: The symbol is a leaf (doesn't call anything) — common for simple data types, constants, or pure functions.
- **Multiple symbols**: Same aggregation behavior as `codegraph_callers`.
- **Standard library calls**: Only project-indexed symbols appear. stdlib/framework calls are not included.

## Voyager Examples

What does this reducer do?

```
codegraph_callees(symbol: "ComposerSaveReducer")
```

What does this API handler call?

```
codegraph_callees(symbol: "search_router")
```

What are the dependencies of this view?

```
codegraph_callees(symbol: "ComposerView")
```

## Tips

- Use to understand what a function/module depends on at a glance.
- Combine with `codegraph_callers` to get both sides: "who calls this?" + "what does this call?".
- When a function has many callees, it may be doing too much — candidate for decomposition.
