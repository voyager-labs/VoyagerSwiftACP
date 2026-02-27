---
globs: apps/macos/**/*.swift
description: 'HTTP client guidelines for macOS app (URLSession, base URL, errors)'
---

# Frontend HTTP Client Guidelines

## Base URL

- Derive from `{PUBLIC_BACKEND_HOST}:{assignedPort}` provided by helper/backend bootstrap.
- Avoid hardcoding `http://localhost:...` in code.

## Requests

- Use `URLSession` or a thin wrapper; set reasonable timeouts.
- Decode using `JSONDecoder`; align with backend envelopes from [03-error-handling-policy.md](/.agents/rules/00-monorepo/03-error-handling-policy.md).
  - Note: search endpoints (`/api/collection*`) currently return non-enveloped `SearchResponse`.
- Map HTTP errors to user-friendly messages; include optional `suggestion`.

## Testability

- Inject clients via TCA Dependencies to allow mocking in tests.
- Avoid static singletons for HTTP calls.

## Retries & cancellation

- Implement short retries for transient network errors.
- Support cancellation for long-running requests; propagate to TCA effects.

References
- Swift-dotenv: [01-frontend-dotenv-integration.md](/.agents/rules/02-macos-helper/01-frontend-dotenv-integration.md)
- Overview: [00-frontend-overview.md](/.agents/rules/01-macos-voyager/00-frontend-overview.md)
