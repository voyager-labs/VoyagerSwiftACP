---
globs: apps/backend/**/*.py
description: 'Backend (FastAPI + Python) overview: structure, entry points, and integration'
---

# Backend (FastAPI + Python) — Overview

## Structure

- **Entry point**: [apps/backend/src/app/main.py](mdc:apps/backend/src/app/main.py)
- **CLI**: [apps/backend/src/app/cli.py](mdc:apps/backend/src/app/cli.py)
- **Configuration**: Environment variable-based config with `.env` file support
- **Package management**: uv (Python 3.13+)

## How to run (high-level)

See [01-dev-run-and-env.md](/.agents/rules/00-monorepo/01-dev-run-and-env.md) for detailed development workflows and environment setup.

## Integration with frontend

- **Lifecycle management**: Frontend launches backend process via helper classes
- **Environment coordination**: Shared `.env` file at repository root
- **API communication**: HTTP requests for AI/ML processing
- **Health checks**: Backend readiness verification before API calls

## Notes

- Backend provides AI/ML capabilities for file operations and search
- See [01-backend-api-contracts.md](/.agents/rules/03-backend/01-backend-api-contracts.md) for API contracts and error handling
- See [02-backend-testing.md](/.agents/rules/03-backend/02-backend-testing.md) for testing guidelines
- See [03-db-migrations.md](/.agents/rules/03-backend/03-db-migrations.md) for database schema management
- See [04-data-modeling-and-schemas.md](/.agents/rules/03-backend/04-data-modeling-and-schemas.md) for Pydantic DTO conventions
- See [05-backend-config.md](/.agents/rules/03-backend/05-backend-config.md) for configuration details
