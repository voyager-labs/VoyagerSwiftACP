---
alwaysApply: true
description: 'Error handling policy across backend and frontend'
---

# Error Handling Policy

## Backend (FastAPI)

- Envelope (preferred default)
  - Success: `{ "data": <payload> }`
  - Error: `{ "error": { "code": "<ERROR_KIND>", "details": "<technical details>" } }`
  - Note: Some existing endpoints do not follow this yet (see "Exceptions" below).
- Status
  - Use precise HTTP codes (400/401/403/404/409/422/429/5xx).
  - Avoid generic 500; surface meaningful failure reasons when safe.
- Validation
  - Prefer explicit `422` with pydantic validation details (sanitized).
- Logging
  - Follow [05-logging-observability.md](/.agents/rules/00-monorepo/05-logging-observability.md) for detailed logging guidelines.
  - Log minimal context; never include secrets or full payloads.

### Exceptions (current codebase)

- Search endpoints under `apps/backend/src/app/search/routes.py` currently return `SearchResponse` as top-level JSON (no `{ "data": ... }` envelope).
- Some failure cases are expressed via `SearchResponse.error` and may still return HTTP status `200`.

## Frontend (SwiftUI + TCA)

- Mapping
  - Map server error codes to user-friendly messages.
  - Prefer inline, non-blocking toasts for recoverable errors.
- Retry & cancellation
  - Implement exponential backoff for transient (429/5xx) cases where safe.
  - Support cancellation for long-running effects; propagate cancellation to UI state.
- UX
  - For destructive operations, request confirmation before execution.
  - Show progress for batch operations; allow user to cancel where feasible.
- State management
  - Keep errors in state as typed structs/enums; prefer lightweight `message` + optional `suggestion`.
