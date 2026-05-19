---
description: "HTTP contracts, status semantics, and schema conventions."
globs: "apps/backend/**/*.py"
---

# Backend API and Schemas

## Must

- Prefer response envelope:
    - Success: `{ "data": ... }`
    - Error: `{ "error": { "code": "...", "details": "..." } }`
- Use precise HTTP status codes (4xx/5xx), not generic fallback errors.
- Use Pydantic models for request/response contracts.
- Keep request and response schemas separated when intent differs.

## Current exception (known)

- Search endpoints under `apps/backend/src/app/search/routes.py` still return top-level `SearchResponse` and may encode failure via `error` while returning `200`.

## Must not

- Break contract shape silently.
- Return raw internal errors to clients.

## Execution steps

1. Check existing route contract and callers.
2. Apply additive schema changes first when possible.
3. Update tests for status code and payload shape changes.

## Verification

- Run backend tests that cover changed routes/contracts.
