# Query Patterns & Workflows

Five patterns that cover the most common CodeGraph use cases. Each pattern names the right tool, shows a concrete query, and explains when it beats grep or manual file reading.

## Pattern 1: Find Who Calls a Symbol

**Tool:** `codegraph_callers`

```
codegraph_callers("ComposerSaveReducer.Action")
```

**When to use:**

- "Where is this action dispatched?"
- "Who creates this dependency?"
- "Which reducers send this effect?"

**Why not grep:** `callers` follows indirect references through protocols, closures, and generic conformances. Grep only catches literal string matches.

**Example output:**

```
## Callers of ComposerSaveReducer.Action (5 found)

### saveButtonTapped (method)
`apps/macos/Voyager/Voyager/Features/Composer/View/ComposerView.swift:142`

### handleKeyboardShortcut (method)
`apps/macos/Voyager/Voyager/Features/Composer/Reducer/ComposerKeyboardReducer.swift:58`
...
```

## Pattern 2: Trace a Call Path from A to B

**Tool:** `codegraph_trace`

```
codegraph_trace("SearchGateway", "search_router")
```

**When to use:**

- "How does the frontend reach this API endpoint?"
- "What's the handler chain between these two symbols?"
- "Trace the call stack from user action to backend handler."

**Key detail:** Trace works across languages (Swift to Python). It stops after 7 hops. If the path exceeds 7 hops, the tool returns a failure message plus a static callee list for the start symbol so you can continue manually.

**Example output:**

```
## Trace: SearchGateway → search_router (3 hops)

1. SearchGateway.performSearch(_:)
   `apps/macos/Voyager/Voyager/Services/SearchGateway.swift:45`
   │
2. HTTPClient.post("/api/search", ...)
   `apps/macos/Packages/HTTPClient/Sources/HTTPClient/HTTPClient.swift:112`
   │
3. search_router
   `apps/backend/app/routers/search.py:28`
```

## Pattern 3: Impact Analysis

**Tool:** `codegraph_impact`

```
codegraph_impact("VoyagerFeaturesComposer")
```

**When to use:**

- Before refactoring a package or module.
- Before changing a public API signature.
- Before moving or renaming files.
- "If I change this, what breaks?"

**Why not file-based search:** Impact analysis works at the symbol level. It finds callers of the symbol, callers of those callers, and so on. More accurate than grep-based "who imports this file" approaches.

**Key detail:** Default depth is 2 (symbol → direct callers → their callers). Depth is clamped between 1 and 10. High depth on core types (like `Equatable` or foundational protocols) produces massive result sets and should be avoided.

**Example output:**

```
## Impact: VoyagerFeaturesComposer (depth 2, 12 affected)

### Direct callers (4)
- ComposerView
- ComposerReducer
- ComposerKeyboardReducer
- ComposerSaveReducer

### Transitive callers (8)
- AppReducer
- SidebarView
- MainWindowReducer
...
```

## Pattern 4: Explore Module Structure

**Tools:** `codegraph_explore` + `codegraph_context`

```
codegraph_explore
codegraph_context("VoyagerFeaturesComposer")
```

**When to use:**

- "What's in this package?"
- "How is this module organized?"
- "Give me a birds-eye view of a new area before I start editing."

**Workflow:**

1. Run `codegraph_explore` to see the top-level package/module list.
2. Pick the module you care about.
3. Run `codegraph_context("ModuleName")` to see its exported symbols, dependencies, and internal structure.

**Why not read 5-10 files:** `explore` + `context` gives you a structured summary in one or two tool calls instead of opening, scanning, and cross-referencing multiple source files.

## Pattern 5: Cross-Language Tracing

**Tool:** `codegraph_trace`

```
codegraph_trace("SearchGateway", "search_router")
```

**When to use:**

- "Which backend endpoint does this frontend call hit?"
- "What Python function handles the API call from this Swift service?"
- "Trace a user action from the macOS app through to the FastAPI backend."

**How it works:** CodeGraph indexes both Swift and Python source trees. When tracing, it resolves HTTP call paths and URL patterns across the language boundary. A Swift `HTTPClient.post("/api/search")` connects to a Python `@router.post("/api/search")` even though the languages and call conventions differ.

**Limitation:** Cross-language tracing relies on string-matched URL paths and shared naming conventions. If the frontend uses a different URL pattern than the backend route definition, the trace may not connect.

## Quick Reference Table

| Pattern         | Tool                  | Input                      | Best for                                     |
| --------------- | --------------------- | -------------------------- | -------------------------------------------- |
| Who calls X     | `callers`             | Symbol name                | Finding dispatch sites, dependency consumers |
| Path A → B      | `trace`               | Two symbol names           | Handler chains, request flows                |
| What breaks     | `impact`              | Symbol name                | Pre-refactor safety check                    |
| Module overview | `explore` + `context` | Module name                | Understanding new code areas                 |
| Swift ↔ Python  | `trace`               | Frontend + backend symbols | Full-stack call tracing                      |
