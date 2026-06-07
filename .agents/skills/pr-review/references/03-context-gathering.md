# 03 — Context Gathering

Run after `02-diff-triage.md`.

## Steps

1. **Read intent context.**
    - Read PR description and linked issues.
    - If intent is absent, summarize the diff goal in 1-2 sentences.
2. **Gather architecture context.**
    - FSD boundary changes: read relevant `Package.swift` files and segment structures.
    - TCA reducer changes: read the owning reducer, parent/child wiring, and dependency client registrations.
    - Persistence/storage changes: read `.agents/rules/30-macos/06-file-backed-storage-invariants.md`.
3. **Use Large-PR parallel exploration when needed.**
    - Dispatch 2-3 focused explore agents for hotspot areas: architecture boundary, async lifecycle/cancellation, credential/storage paths, environment/build settings, helper/XPC contracts, package/public boundaries.
    - After delegating exploration, do not repeat the same searches manually.
    - If background agents are unavailable, read changed files directly in priority order: reducers → models → API clients → views → config.
4. **Use direct tools for targeted checks.**
    - Use `grep` / `ast_grep_search` for pattern checks across changed files.
    - Use `read` for targeted inspection.
    - Use `lsp_diagnostics` for type-level errors in changed files.
5. **Check CodeGraph availability.**
    - Run `mise run codegraph-status` to check whether `.codegraph/` index exists.
    - If available, prefer CodeGraph tools (`codegraph_search`, `codegraph_callers`, `codegraph_impact`, `codegraph_trace`) for symbol-level analysis.
    - If unavailable or stale, use standard grep/read. CodeGraph is optional.
6. **Apply the exploration completion gate.**
    - If background agents were dispatched, collect all `background_output` results before writing any verdict.
    - Never issue `approve`, `comment`, or `request changes` before results are collected.
    - Include `collected and reconciled` status in the final self-check.
    - On agent failure/timeout, mark coverage incomplete and use `comment`, not clean `approve`.

## Detailed tactics

Use `references/review-playbook.md` §Large-PR Context Gathering for agent prompt templates and direct-tool fallback priority.
