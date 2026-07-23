---
name: canonical-tooling-seam
description: Designs and migrates one canonical wrapper, resolver, or adapter seam for shared tooling behavior across hosts while preserving safe platform-local concerns and explicit overrides. Use when duplicate CLI, IDE, CI, or agent commands need consolidation, flags or environment resolution diverge, host adapters or resolver contracts are being designed, bypasses removed, or shared cache and lock policy centralized; not for simple tool selection.
---

# Canonical Tooling Seam

## Purpose and boundary

Use one canonical execution-path owner when several hosts perform the same build, test, deploy, launch, or maintenance operation. Hosts may keep their native invocation shape, but they must not independently recreate resolution, shared-state, safety, or lifecycle policy.

This repo-local candidate remains local until the same semantics have two confirmed consumers. It is not a common/internal skill yet.

This skill owns execution-path architecture: entrypoint inventory, canonical-seam selection, policy injection, override precedence, fail-closed contracts, locking and concurrency, migration, documentation, and a host verification matrix.

`code-tooling` owns a different decision: which code intelligence, build, test, diagnostic, or verification tool to invoke. Load it when choosing tools or executors. Load this skill when making every host follow one execution path.

## Trigger

Use this skill when any of these conditions apply:

- CLI, IDE, CI, and agent/task-runner commands duplicate a build, test, deploy, or launch path.
- Flags, environment variables, working-directory discovery, cache paths, or output paths resolve differently by host.
- A wrapper, resolver, adapter, host bridge, bypass removal, or migration away from direct tool calls is needed.
- Shared caches, locks, run metadata, or destructive maintenance policy need one owner.

## Do not trigger

Do not use this skill for:

- A one-off shell script with one host and no shared execution policy.
- An ordinary build or test failure that needs diagnosis only.
- Tool lookup, code navigation, or selecting a compiler, test runner, or code intelligence tool. Use `code-tooling` for that.

## Expert mindset

Before proposing a seam, answer these four ownership questions:

1. **What is invariant policy?** Defaults, cache identity, safety checks, locks, and metadata need exactly one owner.
2. **What is explicit caller intent?** User-provided flags and approved overrides must survive translation with documented precedence.
3. **What is platform-local mechanics?** IDE schema, CI export, shell invocation, and presentation belong in thin host adapters.
4. **What is tool choice?** Selecting an executor or code-intelligence tool belongs to `code-tooling`, not this skill.

## Workflow

### 1. Inventory every host

List each user-facing and automation entrypoint: CLI tasks, package scripts, IDE tasks or extensions, CI jobs, agent commands, helper scripts, and direct underlying-tool calls. For each, record the operation, arguments, environment, working directory, output/cache paths, and shared state it mutates. Include legacy paths and bypasses, not only the documented path.

### 2. Separate policy from platform-local mechanics

Classify each behavior before designing the seam.

| Class                    | Canonical owner                | Examples                                                                                |
| ------------------------ | ------------------------------ | --------------------------------------------------------------------------------------- |
| Invariant policy         | Resolver or wrapper            | mode defaults, cache identity, output contract, lock ownership, metadata, safety checks |
| Explicit caller intent   | Preserved through contract     | user-provided configuration, cache directory, test filter, deployment target            |
| Platform-local mechanics | Host adapter                   | IDE task schema, CI environment export, shell quoting, process launching                |
| Tool choice              | `code-tooling` or local policy | CodeGraph versus AST search, build executor selection                                   |

Keep only platform mechanics in adapters. Do not move host-specific UI behavior into a generic resolver unless every host needs it.

### 3. Choose the narrowest canonical seam

Before choosing a resolver, wrapper, or adapter, read [design-checklist.md](references/design-checklist.md). For inventory-only work, use the inventory and ownership questions above; do not load adapter patterns until a host adapter must be designed.

Choose the smallest boundary that every host can call without losing explicit intent:

1. A resolver returns a structured execution plan when hosts must retain native process control.
2. A wrapper executes the operation when shared setup, locking, lifecycle, or cleanup must be atomic.
3. An adapter translates one host's configuration into that resolver or wrapper contract.

Prefer one resolver plus thin adapters over a broad abstraction that replaces all host behavior. If shared mutable state exists, the component that mutates it owns the lock and run metadata.

### 4. Define a structured, fail-closed contract

Define typed fields for operation, project root, executable, arguments, environment additions, local payload directory, shared cache directory, cache identity, lock key, and requested overrides. Prefer JSON when the host can parse it and schema or versioning matters; use NUL-delimited arrays at pure shell boundaries when argument boundaries must survive without JSON tooling. Do not parse whitespace-delimited values when paths or arguments may contain spaces.

Validate required fields, types, allowed operations, and path containment before execution. Treat malformed, partial, or unexpected resolver output as an error. Never fall back silently to guessed defaults or a direct underlying-tool call.

### 5. Set precedence and shared-state policy

Document precedence before migration. A safe default is:

1. Explicit command or host override.
2. Explicit environment override allowed by policy.
3. Resolver default derived from repository state.
4. Platform/tool default.

Do not overwrite explicit intent merely to make hosts look identical. Split worktree-local payloads from reusable shared caches. Derive cache identity deterministically from the toolchain, dependency inputs, platform, and relevant mode. Centralize locking, active/running protection, and run metadata at the shared-state owner.

### 6. Migrate all hosts and remove duplicate ownership

Before authoring or changing host adapters, read [host-adapter-patterns.md](references/host-adapter-patterns.md). It covers CLI, IDE, CI, and agent translation; skip it when the task only inventories entrypoints or decides whether a seam is warranted.

Make every inventory entrypoint call the canonical seam through a thin adapter. Preserve supported flags and make adapter translation visible in code or configuration. Remove or hard-fail stale direct paths once the replacement is verified. Do not leave a second owner for cache paths, lock files, resolver defaults, or cleanup policy.

For destructive maintenance, provide dry-run by default or require an explicit confirmation flag. Check that resolved paths stay within allowed roots after symlink resolution. Never surprise users with migration, deletion, or cache eviction.

### 7. Verify and document the one path

Run unit tests for resolution and precedence, adapter tests for each host translation, and end-to-end checks for representative host invocations. Test malformed structured output, explicit overrides, concurrent shared-state access, paths with spaces, and stale bypass behavior. Document the canonical command, adapters, override rules, shared-state locations, and migration status.

## Guardrails

- Split local payloads from shared caches, or concurrent runs can overwrite worktree state and report stale output.
- Make cache keys deterministic from compatibility inputs, or misses waste work and collisions poison reusable state.
- Match each host's shell and platform, or quoting, environment expansion, and executable lookup differ outside a developer's interactive shell.
- Pass plans with JSON or NUL-delimited data, never word splitting, or paths and argument arrays lose their boundaries.
- Lock at the shared-state owner and protect active/running work, or cleanup and replacement race live builds.
- Use dry-run for destructive operations, then require explicit opt-in, or a typo becomes irreversible deletion.
- Resolve paths and symlinks before containment checks, or an apparently allowed path can escape the approved root.
- Leave temporary stale-path observability during migration, or hidden legacy bypasses survive until they cause divergent behavior.
- Do not auto-migrate or delete user data, caches, or outputs without visible intent and recovery guidance, or users lose state without a safe rollback path.

## Delivery checklist

- [ ] Inventory includes documented paths, direct calls, and legacy bypasses.
- [ ] Invariant policy, explicit intent, platform-local mechanics, and tool choice have separate owners.
- [ ] The selected seam has a typed or structured contract and rejects malformed output.
- [ ] Override precedence is documented and tested with explicit caller intent.
- [ ] Shared cache identity, locks, active-run protection, and metadata have one owner where needed.
- [ ] Every host uses an adapter to the same seam, with no duplicate policy owner.
- [ ] Unit, host-adapter, and end-to-end checks cover the verification matrix.
- [ ] Documentation names one canonical path and the supported migration behavior.

## Common mistakes

| Mistake                                           | Why it bites                                                                                                         | Fix                                                                              |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Pointing every host at a copied command           | Flags drift invisibly; a new cache or safety fix reaches only the host someone remembered to edit.                   | Use adapters that call one resolver or wrapper.                                  |
| Treating an IDE task as a policy owner            | An editor setting becomes a hidden source of truth that CI and CLI cannot reproduce.                                 | Keep it as translation and presentation only.                                    |
| Replacing explicit flags with defaults            | A caller requesting an isolated cache or filtered test can silently run against the wrong state or scope.            | Define precedence and pass explicit intent through unchanged.                    |
| Parsing resolver output with shell word splitting | Paths with spaces or argument boundaries change meaning, sometimes turning one intended argument into several.       | Use JSON or NUL-delimited fields and validate them.                              |
| Sharing one mutable worktree payload across runs  | Concurrent worktrees overwrite intermediates and make stale artifacts appear as valid results.                       | Separate local payloads, use deterministic shared caches, and lock shared state. |
| Keeping a direct fallback after migration         | A malformed contract silently bypasses locks, containment checks, and observability precisely when safety is needed. | Fail closed and instrument stale bypasses until removal.                         |

## Example

**Situation:** A macOS project has a CLI task, an IDE task, and CI, each passing different cache flags to a build tool.

**Design:** A resolver emits a JSON plan containing the requested configuration, worktree-local derived output, shared dependency cache, deterministic cache key, and lock key. CLI, IDE, and CI adapters translate their inputs into the same request. The execution wrapper validates the plan, acquires the shared-cache lock, and runs the selected build command. An explicit `--cache-path` remains higher priority than the resolver default. Invalid JSON stops execution instead of falling back to a direct build command.

**Verification:** Unit-test resolution and malformed plans, adapter-test each host request, then run CLI, IDE task, and CI fixture checks including two concurrent cache users.
