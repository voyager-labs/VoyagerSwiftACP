---
alwaysApply: true
description: 'Verification requirements by change scope.'
---

# Verification Requirements

## Applies when
- Any file change.

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
  - `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj`
- Mixed changes:
  - Run both backend and macOS checks relevant to touched code.

## Must not
- Skip verification for non-trivial changes.
- Claim success without command evidence.
