---
description: "Verification requirements by change scope."
alwaysApply: true
---

# Verification Requirements

## Must

- Run checks that match the changed surface area.
- Prefer fast targeted checks first, then broader checks when needed.
- Report exact commands and pass/fail status.

## Execution steps

1. Determine scope: docs-only, backend, macOS, or mixed.
2. Run required checks for that scope.
3. Fix failures or clearly document pre-existing failures.

## Verification matrix

- Docs-only:
    - Confirm links/paths updated where references changed.
- Backend (`apps/backend/**`):
    - `cd apps/backend && uv run pytest`
    - If config/migrations changed, run relevant Alembic command checks.
- macOS (`apps/macos/**`):
    - Tier 1 (targeted): Run SwiftPM package tests for the affected package.
      Example: `swift test` or `xcodebuild test -only-testing:<PackageTests>` for the changed package.
    - Tier 2 (affected targets): Build and test Xcode targets that directly depend on the changed code.
      Example: `xcodebuild build -scheme Voyager-Dev` for compilation check.
    - Tier 3 (broad): Full scheme test. Required only for PR gates, release validation, or cross-cutting changes.
    - For Tier 1/2, document any pre-existing failures in evidence before reporting outcome.
    - Tier 3 failures from code NOT touched by the current task must be documented as pre-existing, not task failures.
- Mixed changes:
    - Run both backend and macOS checks relevant to touched code.

## Diagnostics tool routing

Route language diagnostics through the toolchain configured for this repository:

| Language                            | Diagnostic tool                            | Reason                                                                                                                                                   |
| ----------------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Swift** (`apps/macos/**/*.swift`) | **XcodeBuildMCP** `build_sim` / `test_sim` | `sourcekit-lsp` is disabled in `opencode.json`; `lsp_diagnostics` returns only `No such module` noise. XcodeBuildMCP provides real compiler diagnostics. |
| **Python** (`apps/backend/**/*.py`) | **`lsp_diagnostics`**                      | pyright/pylsp provides accurate type and syntax diagnostics.                                                                                             |

Never call `lsp_diagnostics` for Swift files.

## Must not

- Skip verification for non-trivial changes.
- Claim success without command evidence.
- Call `lsp_diagnostics` on Swift files (`apps/macos/**/*.swift`).
