---
description: "Verification requirements by change scope."
alwaysApply: true
schemaVersion: 2
---

# Verification Requirements

## Outcome

- Run checks that match the changed surface area.
- Prefer fast targeted checks first, then broader checks when needed.
- Report exact commands and pass/fail status.
- Preserve command evidence for backend, macOS, and general verification outcomes.

## Default Actions

1. Determine scope: docs-only, backend, macOS, or mixed.
2. Run required checks for that scope.
3. Fix failures or clearly document pre-existing failures.

## Decision Rules

- Docs-only:
    - Confirm links/paths updated where references changed.
- Backend (`apps/backend/**`):
    - Run the following commands:
        ```bash
        cd apps/backend && uv run pytest
        cd apps/backend && uv run pyright
        cd apps/backend && uv run ruff check
        ```
    - If config/migrations changed, run relevant Alembic command checks.
- macOS (`apps/macos/**`):
    - Tier 1 (targeted): Run the affected SwiftPM package test or the narrowest relevant test target.
    - Tier 2 (affected targets): Build and test Xcode targets that directly depend on the changed code.
    - Tier 3 (broad): Full scheme test. Required only for PR gates, release validation, or cross-cutting changes.
    - Run the repository build/test or lint/format surface that proves each required outcome.
    - Select an executor from the capability matrix in `.agents/skills/code-tooling/SKILL.md`; that skill owns tool availability, session inspection, fallback, and stop decisions.
    - Repository validation surfaces, when selected by that matrix, are:
        ```bash
        mise run macos-build
        mise run macos-test
        mise exec -- swiftlint --config apps/macos/.swiftlint.yml apps/macos
        mise exec -- swiftformat --config apps/macos/.swiftformat apps/macos --verbose
        ```
    - For Tier 1/2, document any pre-existing failures in evidence before reporting outcome.
    - Tier 3 failures from code NOT touched by the current task must be documented as pre-existing, not task failures.
- Mixed changes:
    - Run both backend and macOS checks relevant to touched code.

## Stop Conditions

- Skip verification for non-trivial changes.
- Claim success without command evidence.

## Verification

- Run `git diff --check` to detect whitespace errors and conflict markers.
- Record the selected scope, commands, tiers, pass/fail status, and any pre-existing-failure classification in task or PR evidence.
