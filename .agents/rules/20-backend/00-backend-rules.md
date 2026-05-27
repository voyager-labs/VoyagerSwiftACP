---
description: "Backend implementation rules for FastAPI/Python modules."
globs: "apps/backend/**/*.py"
---

# Backend Rules

## Must

- Keep layering clear: `app` (entry/api), `core` (domain logic), `infra` (persistence/integration), `utils` (shared helpers).
- Keep types explicit in public APIs.
- Follow existing project scripts (`uv`) for run/test tasks.
- Keep request handling thin; place business logic in service/domain code.

## Must not

- Put persistence/integration concerns directly in route handlers.
- Introduce global mutable state for request flow.

## Execution steps

1. Locate existing domain pattern near target module.
2. Mirror naming and module layout.
3. Add or update tests for changed behavior.

## Verification

- Run `cd apps/backend && uv run pytest`.
