---
description: "HTTP contracts, status semantics, and schema conventions."
globs: "apps/backend/**/*.py"
schemaVersion: 2
---

# Backend API and Schemas

## Outcome

- Prefer response envelope:
    - Success: `{ "data": ... }`
    - Error: `{ "error": { "code": "...", "details": "..." } }`
- Use precise HTTP status codes (4xx/5xx), not generic fallback errors.
- Use Pydantic models for request/response contracts.
- Keep request and response schemas separated when intent differs.

## Default Actions

1. Check the existing route contract and callers.
2. Apply additive schema changes first when possible.
3. Update tests for status code and payload shape changes.

## Decision Rules

- Search endpoints under `apps/backend/src/app/search/routes.py` still return top-level `SearchResponse` and may encode failure via `error` while returning `200`.

## Stop Conditions

- Break contract shape silently.
- Return raw internal errors to clients.

## Verification

- Run backend tests that cover changed routes/contracts.
