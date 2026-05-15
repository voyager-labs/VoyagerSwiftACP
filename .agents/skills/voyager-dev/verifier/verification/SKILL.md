---
name: verification
description: Applies final Voyager macOS verification gates. Use after implementation or review to run focused verification, lint/format decisions, boundary checks, and XcodeBuildMCP-backed build/test flows.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: verifier
    shape: verification
---

# Voyager Dev Verification Verifier

## Instructions

1. Load `references/verification.md`.
2. Add `references/xcodebuildmcp-workflow.md` when build/test execution needs XcodeBuildMCP.
3. Apply task-shape expectations, search-based checks, layer checks, and boundary/test checks based on changed concerns.
4. For multi-step async flows, verify cancellation, superseded requests, and stale completions do not commit success state.
5. Report verification evidence and any reduced confidence explicitly.
