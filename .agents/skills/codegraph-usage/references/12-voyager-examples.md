# Voyager-Specific Query Examples

Real-world queries you can run against the Voyager codebase. Each example shows the question, the exact query, and what you should expect to see in the result.

## TCA Reducer Call Chain

**Question:** "Where is this reducer's Action called from?"

```
codegraph_callers("ComposerSaveReducer.Action")
```

**What you get:**

A list of call sites where `ComposerSaveReducer.Action` cases are dispatched. This typically includes:

- View layer (`ComposerView`) where user interactions (button taps, keyboard shortcuts) create actions.
- Parent reducer (`ComposerReducer`) where scoped actions are delegated.
- Effect callbacks where `.success` or `.failure` response actions are sent.

Each result shows the enclosing function name, its kind (method, property, closure), and the file/line location.

**How to read the results:**

If you see a caller in a view file, that's the user-triggered dispatch site. If you see a caller in another reducer, that's programmatic delegation or effect response. Use this to understand the full action lifecycle before modifying reducer logic.

## FastAPI Route Tracing

**Question:** "What is the handler chain for this endpoint?"

```
codegraph_trace("search_router", "collection_search")
```

**What you get:**

A multi-hop path from the route definition to the final handler function. A typical result looks like:

```
1. search_router (route definition)
   `apps/backend/app/routers/search.py:28`
   │
2. search_controller.perform_search (method)
   `apps/backend/app/controllers/search_controller.py:45`
   │
3. collection_search (function)
   `apps/backend/app/services/search_service.py:112`
```

**How to read the results:**

The first hop is the FastAPI route decorator. The second hop is the controller or middleware layer. The final hop is the service or data layer function. Use this when you need to understand the full backend request handling path, especially when debugging or modifying API behavior.

## Package Dependency Analysis

**Question:** "Which other packages use this package?"

```
codegraph_impact("VoyagerFeaturesComposer")
```

**What you get:**

A two-level caller tree showing direct and transitive dependents of the `VoyagerFeaturesComposer` package.

```
### Direct callers (3)
- VoyagerApp (main app target)
- VoyagerFeaturesSidebar (sibling feature package)
- VoyagerTests (test target)

### Transitive callers (5)
- VoyagerUITests
- OnboardingHost
...
```

**How to read the results:**

Direct callers are packages or targets that import `VoyagerFeaturesComposer` directly. Transitive callers are further downstream. Use this before moving types between packages, changing public APIs, or splitting a package into smaller units.

## Cross-Language Tracing (Swift to Python)

**Question:** "What is the full path from a Swift gateway call to the Python backend handler?"

```
codegraph_trace("SearchGateway", "search_router")
```

**What you get:**

A trace that crosses the Swift-to-Python language boundary:

```
1. SearchGateway.performSearch(_:)
   `apps/macos/Voyager/Voyager/Services/SearchGateway.swift:45`
   │ calls
2. HTTPClient.post("/api/search", ...)
   `apps/macos/Packages/HTTPClient/Sources/HTTPClient/HTTPClient.swift:112`
   │ resolves to
3. search_router
   `apps/backend/app/routers/search.py:28`
```

**How to read the results:**

The first hop is the Swift service layer. The second hop is the shared HTTP client. The third hop is the Python FastAPI route definition. The cross-language link is resolved by matching URL path strings (`/api/search`) between the Swift HTTP call and the Python route decorator.

Use this when you need to trace a bug from the frontend to the backend, understand the full data flow for a feature, or verify that API changes in one language are reflected in the other.

## Common Follow-Up Queries

After running one of the examples above, these follow-ups are useful:

| Goal                          | Follow-up query                                                            |
| ----------------------------- | -------------------------------------------------------------------------- |
| See the symbol's signature    | `codegraph_node("SymbolName")`                                             |
| Check if a symbol is exported | `codegraph_context("PackageName")`                                         |
| Find similar symbols          | `codegraph_search(query: "partial_name")`                                  |
| Get the symbol's source code  | `codegraph_node("SymbolName")` then read the file at the reported location |
