---
globs: apps/backend/**/*.py
description: 'HTTP API guidance: endpoints, contracts, and versioning for FastAPI'
---

# Backend API Contracts (FastAPI)

## API Structure

- **Entry point**: [apps/backend/src/app/main.py](mdc:apps/backend/src/app/main.py)
- **Organization**: Organize routers/services by domain
- **Schemas**: Keep request/response models near router or in `schemas` module

## Response Standards

- **Success responses (preferred)**: Use envelope pattern (see [03-error-handling-policy.md](/.agents/rules/00-monorepo/03-error-handling-policy.md))
- **Error responses**: Consistent error structure and HTTP status codes
- **Validation**: Prefer explicit `422` validation errors; avoid generic `500`
- **Data models**: Use Pydantic schemas (see [04-data-modeling-and-schemas.md](/.agents/rules/03-backend/04-data-modeling-and-schemas.md))

Note: Existing search endpoints (`/api/collection*`) currently return `SearchResponse` top-level and may use `SearchResponse.error` for failures.

## API Patterns

- **GET endpoints**: Return data with optional pagination metadata
- **POST/PUT endpoints**: Return created/updated resource with appropriate status
- **DELETE endpoints**: Return `204` (no content) or confirmation data
- **Batch operations**: Use `202` (accepted) for async processing
- **Content type**: Support `application/json` as primary content type

## Versioning

- **Current**: `/api` prefix (no explicit versioning)
- **If introducing versioning**: Prefer `/api/v1` initially, `/api/v2` for breaking changes
- **Compatibility**: Maintain backward compatibility within major versions
- **Deprecation**: Use `Deprecation` header for sunset timeline

## Documentation

- **OpenAPI**: Ensure app exposes OpenAPI and docs (FastAPI defaults)
- **Testing**: Test API contracts and endpoints (see [02-backend-testing.md](/.agents/rules/03-backend/02-backend-testing.md))
- **Examples**: Include request/response examples for each endpoint
