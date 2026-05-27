# codegraph_search

Full-text symbol and file name search across the indexed codebase.

## Parameters

| Name          | Type   | Required | Default         | Constraints                                                                                  |
| ------------- | ------ | -------- | --------------- | -------------------------------------------------------------------------------------------- |
| `query`       | string | **Yes**  | —               | Search term for symbol/file names                                                            |
| `kind`        | string | No       | —               | One of: `function`, `method`, `class`, `interface`, `type`, `variable`, `route`, `component` |
| `limit`       | number | No       | 10              | Clamped to 1–100 at runtime                                                                  |
| `projectPath` | string | No       | current project | Path to an initialized CodeGraph project                                                     |

## Return Shape

Text response formatted as:

```
## Search Results (N found)

### SymbolName (kind)
`filePath:line`
signature (if available)
```

If no results: `No results found for "..."`

## Behavior

- Performs full-text search on symbol names and file paths.
- When `kind` is specified, filters results to only that symbol type.
- `limit` controls max results; the tool clamps it to 1–100 regardless of input.
- Returns location information (file:line) and optionally the symbol signature.

## Edge Cases

- **No results**: Returns `No results found for "..."` — try broader query terms.
- **Ambiguous names**: Multiple symbols with the same name all appear in results.
- **Partial matches**: Supports partial string matching, not just exact names.
- **Very common names** (e.g., `init`, `view`): Use `kind` filter to narrow down.

## Voyager Examples

Find all search-related functions:

```
codegraph_search(query: "search", kind: "function")
```

Find the ComposerSave reducer:

```
codegraph_search(query: "ComposerSave")
```

Find all route definitions in the backend:

```
codegraph_search(query: "router", kind: "route")
```

## Tips

- Start with `codegraph_search` when you know a symbol name but not its exact location.
- Use `kind` to filter noisy results — especially useful for common names like `init`, `view`, `update`.
- For "what does this symbol look like?" follow up with `codegraph_node` using the result.
- For "who uses this?" follow up with `codegraph_callers`.
