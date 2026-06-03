# codegraph_trace

Traces the call path from symbol A to symbol B. The primary tool for understanding how code flows between two points.

## Parameters

| Name          | Type   | Required | Default         | Constraints                              |
| ------------- | ------ | -------- | --------------- | ---------------------------------------- |
| `from`        | string | **Yes**  | —               | Starting symbol name                     |
| `to`          | string | **Yes**  | —               | Target symbol name                       |
| `projectPath` | string | No       | current project | Path to an initialized CodeGraph project |

## Return Shape

On success:

```
## Trace: from → to

### Step 1: StartingSymbol
`filePath:line`
[source body]

### Step 2: IntermediateSymbol
`filePath:line`
[source body]

... (up to 7 hops)

### Destination callees:
- callee1 (kind) - file:line
- callee2 (kind) - file:line
```

On failure (no path found):

```
No direct call path found from "..." to "..."

This may be due to dynamic dispatch, protocol-based calls, or the path requiring more than 7 hops.

Static callees of the starting symbol:
- callee1 (kind) - file:line
```

## Behavior

- Finds the **shortest call path** using only `calls` edges in the graph.
- Tries up to 3 candidate symbols for each side (from/to) to handle name ambiguity.
- Maximum of 7 hops — if the path is longer, it reports failure.
- Inlines source body for each hop in the path.
- Lists the destination symbol's immediate callees at the end.
- When the path breaks due to dynamic dispatch (protocols, closures, virtual calls), reports the break point and shows the start symbol's static callees instead.

## Edge Cases

- **Dynamic dispatch break**: The most common failure mode. When A calls B through a protocol/interface, the static graph may not have the edge. The tool explains this and shows the last known static call.
- **No path found**: Returns explanation + start symbol's static callees for manual inspection.
- **Symbol not found**: Returns `Symbol "..." not found`.
- **More than 7 hops**: Path is too deep; returns failure.
- **Multiple matching symbols**: Tries up to 3 candidates per side and returns the first successful path.

## Voyager Examples

Trace Swift frontend to Python backend:

```
codegraph_trace(from: "SearchGateway", to: "search_router")
```

Trace a TCA action to its effect:

```
codegraph_trace(from: "saveButtonTapped", to: "saveComposer")
```

Trace a route handler to a database call:

```
codegraph_trace(from: "search_router", to: "collection_search")
```

## Tips

- This is CodeGraph's **killer feature** — no other tool in the stack can trace call paths across the codebase, especially across languages.
- Cross-language tracing (Swift → Python) is a key use case for Voyager's architecture.
- When trace fails due to dynamic dispatch, use `codegraph_callers` on the target to find who calls it, then manually connect the dots.
- For "who calls this single symbol?" use `codegraph_callers` instead — it's simpler and more reliable.
