---
name: verification
description: Applies final Voyager macOS verification gates. Use after implementation or review to run focused verification, lint/format decisions, SwiftPM package integration checks, boundary checks, and XcodeBuildMCP-backed build/test flows.
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
3. Add `references/package-integration-verification.md` when local SwiftPM package products, targets, dependencies, package manifests, or external consumers change.
4. Add `references/swift6-package-rules.md` when creating packages, adding or moving types into packages, editing Package.swift, or fixing Sendable errors.
5. Apply task-shape expectations, search-based checks, layer checks, and boundary/test checks based on changed concerns.
6. For multi-step async flows, verify cancellation, superseded requests, and stale completions do not commit success state.
7. Report verification evidence and any reduced confidence explicitly.
