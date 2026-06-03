# codegraph_node

Returns detailed information about a single symbol — definition, signature, trail (call chain), and optionally source code.

## Parameters

| Name          | Type    | Required | Default         | Constraints                              |
| ------------- | ------- | -------- | --------------- | ---------------------------------------- |
| `symbol`      | string  | **Yes**  | —               | Symbol name to look up                   |
| `includeCode` | boolean | No       | false           | Whether to include source code           |
| `projectPath` | string  | No       | current project | Path to an initialized CodeGraph project |

## Return Shape

```
## SymbolName (kind)

- Location: filePath:line
- Signature: (if available)

### Trail
#### Calls:
- CalleeName (kind) - file:line
#### Called by:
- CallerName (kind) - file:line
```

When `includeCode=true`:

- Leaf symbols (functions, methods): returns full source body.
- Container symbols (class, struct, enum, protocol, module): returns **member outline** instead of full body.

## Behavior

- Returns the most detailed view of a single symbol.
- `includeCode=false` (default): Fast, returns metadata + trail only.
- `includeCode=true`: Returns source code for leaf symbols, member outline for containers.
- Container types: `class`, `struct`, `interface`, `trait`, `protocol`, `enum`, `namespace`, `module`.
- Trail shows both outgoing calls and incoming callers for context.

## Edge Cases

- **Ambiguous exact matches**: Multiple symbols with exact same name — adds a note about ambiguity.
- **Empty trail**: Symbol has no calls/callers — trail section is omitted.
- **Container with `includeCode=true`**: Returns outline, not full body. This prevents massive output for large classes.
- **Symbol not found**: Returns not found message.

## Voyager Examples

Get details about a reducer:

```
codegraph_node(symbol: "ComposerSaveReducer", includeCode: true)
```

Get details about a route handler:

```
codegraph_node(symbol: "search_router", includeCode: false)
```

Get the structure of a class:

```
codegraph_node(symbol: "SearchGateway", includeCode: true)
```

## Tips

- Use after `codegraph_search` to get detailed info about a specific result.
- `includeCode=false` is fast and token-efficient — use it when you just need location and relationships.
- `includeCode=true` for containers gives you a member outline — great for understanding class/struct structure without reading the whole file.
- The Trail section gives you a quick "who calls this / what does this call" overview without needing separate callers/callees calls.
