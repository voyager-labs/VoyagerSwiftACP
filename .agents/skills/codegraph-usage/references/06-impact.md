# codegraph_impact

Analyzes the blast radius of changing a symbol. Answers "what breaks if I change this?"

## Parameters

| Name          | Type   | Required | Default         | Constraints                              |
| ------------- | ------ | -------- | --------------- | ---------------------------------------- |
| `symbol`      | string | **Yes**  | —               | Symbol name to analyze                   |
| `depth`       | number | No       | 2               | Clamped to 1–10 at runtime               |
| `projectPath` | string | No       | current project | Path to an initialized CodeGraph project |

## Return Shape

```
## Impact: "SymbolName" affects N symbols

### filePath
- SymbolA (kind) - line
- SymbolB (kind) - line

### anotherPath
- SymbolC (kind) - line
...
```

If symbol not found: `Symbol "..." not found in the graph...`

## Behavior

- Collects the **transitive dependency graph** — everything that depends on the given symbol, up to `depth` levels.
- `depth=1`: Direct dependents only (who imports/calls this directly).
- `depth=2`: Direct + their dependents (cascading impact).
- Higher depth = wider blast radius, but more noise.
- Results are **grouped by file** for easy scanning.
- Deduplicates nodes and edges across multiple matching symbols.

## Edge Cases

- **Depth too high** (e.g., 10): Returns massive results for core symbols. Start with `depth=2`.
- **No dependents**: The symbol is isolated — safe to change without downstream impact.
- **Core types** (e.g., `String`, `Result`): Will return thousands of results. Not useful for primitive types.
- **Multiple matching symbols**: Aggregates impact across all matches.

## Voyager Examples

What breaks if I change this package's public API?

```
codegraph_impact(symbol: "VoyagerFeaturesComposer")
```

What's the blast radius of changing this reducer's state?

```
codegraph_impact(symbol: "ComposerSaveReducer.State", depth: 3)
```

Who depends on this shared utility?

```
codegraph_impact(symbol: "SearchGateway", depth: 1)
```

## Tips

- **Always run before refactoring** — this is your safety check.
- Start with `depth=2` for a reasonable overview. Increase only if needed.
- Compare with `macos_checks.py --changed` for file-path-based impact — CodeGraph catches symbol-level dependencies that file mapping misses.
- For packages/modules, use the package name as the symbol.
