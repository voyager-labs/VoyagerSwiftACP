# Host Adapter Patterns

An adapter translates host inputs to a canonical request, invokes the resolver or wrapper, and presents results in host-native form. It does not calculate cache paths, choose defaults, or bypass safety checks.

## Generic adapters

| Host              | Adapter input                                      | Adapter responsibility                                                     | Avoid                                                      |
| ----------------- | -------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------- |
| CLI               | Positional arguments, flags, environment           | Parse explicit intent, pass an argument array, map exit status             | Rebuilding resolver defaults in shell.                     |
| IDE               | Task JSON, launch configuration, extension setting | Convert configuration to request fields and render diagnostics             | Direct underlying-tool commands with copied flags.         |
| CI                | Job variables, matrix values, workspace metadata   | Pass approved values, expose artifacts and logs                            | Separate cache-key or lock policy per workflow.            |
| Agent/task runner | Structured action parameters and workspace context | Validate workspace identity, call canonical path, return structured result | Free-form shell interpolation or unvalidated plan parsing. |

## Structured handoff

Prefer a JSON request file or stdin/stdout protocol when a host can handle JSON. In POSIX shell boundaries, use NUL-delimited fields and arrays. Quote paths at every shell boundary, but do not use quoting as a substitute for a structured contract.

```json
{
    "operation": "test",
    "project_root": "/workspace/project",
    "requested": { "configuration": "Debug", "cache_dir": null },
    "host": "ci"
}
```

The resolver can return a validated plan with arguments as an array, environment additions, separate local and shared paths, a deterministic cache key, and a lock key. The wrapper rejects a response that cannot be parsed or validated.

## Platform examples

### Xcode and macOS

- A CLI task, Xcode scheme helper, and editor task can send scheme, configuration, destination, and explicit DerivedData intent to the same resolver.
- Keep scheme UI, simulator selection, and editor task schema in their adapters.
- Keep `DerivedData` and `-clonedSourcePackagesDirPath` writable checkouts worktree-local by default. They contain build or clone state that concurrent worktrees must not share.
- Share only reusable `-packageCachePath` package-support/download cache when compatibility and locking make it safe. Do not confuse cloned `SourcePackages` with `packageCachePath`.
- A wrapper may own the worktree-local paths, shared package-cache identity, and a lock around shared package-cache mutation.
- Do not assume an interactive zsh environment. Declare the shell and resolve paths relative to the repository contract.

### npm or pnpm web projects

- `npm run`, `pnpm run`, editor tasks, and CI should call one script or resolver for mode, workspace root, output location, and cache policy.
- Preserve explicit `-- --mode production`, filter, and cache overrides through argument arrays.
- Keep package-manager invocation and CI artifact upload in adapters; do not let each adapter invent a cache key.
- Include lockfile, runtime version, platform, and relevant build mode in a shared cache identity when those inputs affect compatibility.

### uv and pytest backends

- Shell commands, IDE test integrations, and CI jobs can request test scope, Python environment, and approved cache overrides through one test wrapper or resolver.
- Preserve explicit pytest selectors, markers, and `uv` environment choices.
- Keep IDE test-discovery settings and CI report publishing outside the resolver.
- Protect shared environment or dependency-cache mutations with a central lock when concurrent workspaces can touch them.

## Adapter tests

For every host, assert that the adapter emits the same canonical request for equivalent intent, preserves an explicit override, and reports malformed resolver output as a failure. Add an end-to-end fixture that proves the host did not invoke the underlying tool directly.
