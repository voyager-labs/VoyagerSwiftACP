---
globs: apps/backend/**/*.py
description: 'Database migration and backend configuration rules.'
---

# Backend Migrations and Config

## Applies when
- Editing config loading, env handling, DB models, or Alembic migrations.

## Must
- Keep config source of truth in `apps/backend/src/app/config.py`.
- Respect env precedence:
  1. Process env
  2. `.env.{BACKEND_MODE}`
  3. `.env.{APP_ENV}`
- Keep migrations atomic and reversible when practical.
- Keep seed/bootstrap logic outside migration bodies.

## Alembic commands
- Create migration:
  - `cd apps/backend && uv run alembic -c src/infra/db/alembic.ini revision --autogenerate -m "<message>"`
- Apply migration:
  - `cd apps/backend && uv run alembic -c src/infra/db/alembic.ini upgrade head`

## Must not
- Hardcode secrets in config defaults.
- Mix schema migration and large data migration logic in one revision.

## Verification
- Run relevant Alembic command checks.
- Run `cd apps/backend && uv run pytest` for changed config/runtime behavior.
