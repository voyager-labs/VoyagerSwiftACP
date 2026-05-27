# Limitations & Gotchas

CodeGraph is a tree-sitter-based sidecar tool, not a compiler. It fills a specific niche (fast structural exploration) but cannot replace the compiler, SourceKit-LSP, or existing verification tooling. Read this before relying on CodeGraph results for critical decisions.

## Indexing Limitations

### ObjC Bridge Headers: Partial Support

Objective-C bridge headers (`-Bridging-Header.h`) are partially indexed. You may see incomplete caller lists for symbols that cross the Swift/ObjC boundary via bridging. If a symbol is defined in ObjC and used through a bridge header, CodeGraph might not find all Swift-side callers.

### File Size Limit

Files larger than 1 MB are excluded from indexing entirely. In practice, this rarely affects Voyager source files, but generated code or bundled data files that happen to live in the source tree will be invisible to CodeGraph.

### tree-sitter, Not the Compiler

CodeGraph parses with tree-sitter. It does not run the Swift or Python type checker. Consequences:

- Generic type inference is not resolved. A call to `someGenericFunc(myValue)` may not trace through to the correct specialization.
- Conditional conformances and `#if` compiler directives are parsed as-is; inactive branches are still indexed.
- Protocol witness tables are not fully resolved. A call that goes through an existential (`any Protocol`) may show fewer callers than the compiler would resolve.

### Swift Macro Attributes Cannot Be Traced

Swift macros (e.g., `@Observable`, `@DependencyClient`) expand at compile time. CodeGraph sees the macro attribute but not the generated code. If a call path goes through macro-generated code, the trace will stop at the macro boundary.

## Runtime Limitations

### Index Freshness

The index auto-updates only while the MCP server is running (which means while `opencode` is active). If you edit files outside of an opencode session, the index becomes stale. Run this manually to re-index:

```
just codegraph-reindex
```

### Trace Max 7 Hops

`codegraph_trace` stops after 7 hops. If the actual call path is deeper:

- The tool returns a failure message.
- It also returns the static callee list of the start symbol, so you can continue the trace manually from there.
- Workaround: Pick an intermediate symbol from the partial result and trace from there to the destination.

### Impact Depth Default and Clamping

- Default depth for `codegraph_impact`: **2** (direct callers + one level of transitive callers).
- Depth is clamped between **1** and **10**.
- High depth (5+) on core types (`String`, `Equatable`, `Identifiable`, app-level protocols) produces result explosions. The output can exceed the MCP response limit and get truncated. Start at depth 2 and increase only if needed.

### explore Does Not Support Natural Language

`codegraph_explore` matches on symbol names, file names, and code terms. It does not understand questions like "find the authentication module." For natural language queries, use `codegraph_context` instead, which provides a narrative summary of a module.

## Tool Boundaries

### Not a Replacement for SourceKit-LSP

CodeGraph does not provide:

- Go-to-definition with full type resolution.
- Rename refactoring.
- Real-time diagnostics.
- Build error detection.

Use SourceKit-LSP (via your editor or the `voyager-lsp-context` skill) for these tasks.

### Not a Replacement for macos_checks.py

The `scripts/dev/macos_checks.py` verification pipeline runs actual compilation and test targets. CodeGraph cannot detect:

- Missing imports that only fail at compile time.
- Type mismatches that the compiler catches.
- Test failures.

### Not a Required Tool

CodeGraph is an optional sidecar. The Voyager codebase builds, tests, and ships without it. If CodeGraph is down or the index is corrupted, you lose exploration convenience but no correctness guarantees.

## When to Avoid CodeGraph

| Situation                                   | Use instead                                  |
| ------------------------------------------- | -------------------------------------------- |
| Need exact type information                 | SourceKit-LSP, `swift typecheck`             |
| Need compiler errors                        | `xcodebuild build`                           |
| Need test results                           | `xcodebuild test` or `swift test`            |
| Need to rename a symbol across the codebase | LSP rename, not `search` + manual edit       |
| Working on files over 1 MB                  | `grep`, `rg`, or read the file directly      |
| Tracing through macro-generated code        | Read the macro expansion or use the compiler |
