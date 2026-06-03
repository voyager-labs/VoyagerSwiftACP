# codegraph_context

Returns the surrounding context for a task or symbol — the primary "what is going on here?" tool.

## Parameters

| Name          | Type    | Required | Default         | Constraints                                                 |
| ------------- | ------- | -------- | --------------- | ----------------------------------------------------------- |
| `task`        | string  | **Yes**  | —               | Natural language description of what you want to understand |
| `maxNodes`    | number  | No       | 20              | Maximum number of nodes to include in context               |
| `includeCode` | boolean | No       | true            | Whether to include source code snippets                     |
| `projectPath` | string  | No       | current project | Path to an initialized CodeGraph project                    |

## Return Shape

Markdown-formatted context summary including:

- Relevant symbols and their relationships
- Source code snippets (when `includeCode` is true)
- File locations and line numbers

If the heuristic detects a feature request pattern, appends a reminder to ask the user.

## Behavior

- The primary exploration tool — describe what you want to understand in natural language.
- Builds a context graph around the query, pulling in related symbols, files, and code.
- When `CLAUDE_SESSION_ID` exists, marks the session as "consulted" for analytics.
- If the query looks like a feature request rather than a code question, appends a reminder to ask the user.

## Edge Cases

- **Vague queries**: Returns broader context; try being more specific for focused results.
- **No relevant symbols**: Returns a message indicating no context found.
- **Large context**: `maxNodes` controls output size. Reduce if response is too long.

## Voyager Examples

Understand a reducer you've never seen:

```
codegraph_context(task: "How does ComposerSaveReducer handle save operations?")
```

Understand a backend endpoint:

```
codegraph_context(task: "How does the search API endpoint work end to end?")
```

Understand a package structure:

```
codegraph_context(task: "What is VoyagerFeaturesComposer and what does it contain?", includeCode: false)
```

## Tips

- Use `codegraph_context` as your **first call** when encountering unfamiliar code.
- It's the most versatile tool — handles "how does X work?", "what's around this?", "explain this module".
- For precise call chains, use `codegraph_trace` or `codegraph_callers` instead.
- Set `includeCode: false` when you only need structure, not source — saves tokens.
