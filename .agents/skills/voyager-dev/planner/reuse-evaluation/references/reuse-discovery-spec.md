# Voyager Dev Reuse Discovery Spec

## Goal

Before adding code, discover whether equivalent or near-equivalent functions, variables, types, reducers, clients, or objects already exist and can be reused.

## Inputs

- Target change request (feature/fix/refactor)
- Candidate paths (`apps/macos/**`, and related shared layers)
- Expected behavior and boundaries

## Search workflow

1. Run symbol discovery:
    - `lsp_symbols` for type/function names
    - `lsp_find_references` for call graph and usage density
2. Run pattern discovery:
    - `ast_grep_search` for reducer/view/effect patterns
    - `grep` for naming variants and domain keywords
3. Run similarity pass:
    - Find same responsibility with different names
    - Find partial matches that can be wrapped/adapted
    - Check whether an existing model/object can absorb the change by adding properties or focused behavior instead of introducing a new peer type

## Parallel subagent pattern

- `explore-A`: symbol and API surface discovery
- `explore-B`: behavior/pattern similarity discovery
- `explore-C`: architecture boundary scan (layer and dependency direction)

Run these in parallel, then merge results into a single candidate table.

## Candidate table format

For each candidate include:

- `symbol`
- `path`
- `why-similar`
- `gap`
- `reuse-option` (`extend` | `direct` | `adapter` | `new` | `reject`)
- `why-not-extend-existing` (required when choosing `adapter` or `new`)

## Exit condition

Discovery is complete only when at least one pass has been executed for symbols, patterns, and references.

## Reuse-first rule

- Default order is: `extend existing` -> `direct reuse` -> `adapter` -> `new`.
- Choose `new` only when the change forms a new responsibility with its own stable name, ownership boundary, or lifecycle.
- If the proposal adds a wrapper only to preserve compatibility during refactor, require proof that the wrapper owns real translation, protection, or migration behavior.
