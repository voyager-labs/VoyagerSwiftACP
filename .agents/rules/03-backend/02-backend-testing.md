---
globs: apps/backend/**/*.py
description: 'Backend testing policy (pytest, TestClient, structure)'
---

# Backend Testing Policy

## Structure

- Tests live under [apps/backend/tests/](mdc:apps/backend/tests/) using `pytest`.
- Name files `*_test.py`; group by feature/domain.
- Keep fixtures in `conftest.py` where shared.

## Running tests

- From [apps/backend](mdc:apps/backend): `uv run pytest`

## FastAPI testing

- Prefer `TestClient` for router tests; test success and error envelopes.
- Use factories/builders for payloads to avoid brittle tests.

## Contracts and regression

- Add/modify tests when changing API contracts or status codes (see [01-backend-api-contracts.md](/.agents/rules/03-backend/01-backend-api-contracts.md)).
- Cover pagination/filtering where applicable.
- Include minimal integration tests for key flows (happy path + failure).
- Test error responses according to [03-error-handling-policy.md](/.agents/rules/00-monorepo/03-error-handling-policy.md).

## Guidelines

- Isolate side effects; use temp dirs/DBs.
- Cover contracts for 2xx and error responses.
- Add smoke tests for critical flows.
