# codegraph_callers

Finds all locations that call a specific symbol. Answers "who uses this?"

## Parameters

| Name          | Type   | Required | Default         | Constraints                              |
| ------------- | ------ | -------- | --------------- | ---------------------------------------- |
| `symbol`      | string | **Yes**  | —               | Symbol name to search for                |
| `limit`       | number | No       | 20              | Clamped to 1–100 at runtime              |
| `projectPath` | string | No       | current project | Path to an initialized CodeGraph project |

## Return Shape

```
## Callers of SymbolName (N found)

- CallerName (kind) - filePath:line
- CallerName (kind) - filePath:line
...
```

If symbol not found: `Symbol "..." not found in the graph...`
If no callers: `No callers found for "..." — this symbol may not be called by other indexed code.`

## Behavior

- Searches for all symbols matching the given name.
- For each matching symbol, collects all distinct caller locations.
- Aggregates results across all matches (handles overloaded functions, same-named symbols in different modules).
- `limit` controls max callers shown; clamped to 1–100.

## Edge Cases

- **Symbol not found**: The name doesn't exist in the index. Try `codegraph_search` first to find the exact name.
- **No callers**: The symbol exists but nothing calls it (entry points, top-level functions, unused code).
- **Multiple symbols with same name**: All are included — you may see callers for a different symbol than intended. Check file paths.
- **Indirect calls via protocols**: Tree-sitter may not capture protocol-based dispatch. Some callers may be missing.

## Voyager Examples

Who dispatches this TCA action?

```
codegraph_callers(symbol: "ComposerSaveReducer.Action")
```

Who creates this dependency?

```
codegraph_callers(symbol: "SearchGateway")
```

Who calls this API endpoint handler?

```
codegraph_callers(symbol: "handle_search")
```

## Tips

- Most commonly used tool for refactoring safety — run it before changing any shared symbol.
- When callers are empty, it might mean: (a) the symbol is an entry point, or (b) callers are indirect (protocols/closures).
- For a complete dependency picture, combine with `codegraph_impact` which traces deeper.
- Always check the file paths in results — same-name symbols from different modules may appear mixed.
