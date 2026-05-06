---
name: testing
description: Selects, runs, and analyzes Voyager macOS and SwiftPM tests. Use when choosing focused tests, fixing failures, checking TestStore behavior, or proving downstream reducer/effect chains.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: verifier
    shape: testing
---

# Voyager Dev Testing Verifier

## Instructions

1. Load `references/testing-playbook.md`.
2. Add `../verification/references/xcodebuildmcp-workflow.md` when Xcode project listing, build, or test execution is needed.
3. Run focused tests first, then broaden only when shared reducers, package APIs, or dependencies changed.
4. Distinguish routing-only assertions from downstream execution-chain proof.
5. Report commands, pass/fail result, first failure summary, and rerun outcome.
