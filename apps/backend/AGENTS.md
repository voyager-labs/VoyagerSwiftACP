# Agent Instructions (Backend)

Scope: `apps/backend/**`

## Implementation boundaries

- Keep route handlers thin; put business logic in services or domain modules.
- Keep persistence and provider integrations out of route handlers.
- For search API changes, preserve the current top-level `SearchResponse`, convert-only behavior, and `error` field contract documented in `README.md`.
- Do not expose raw tracebacks, filesystem paths, provider payloads, or internal exception details in API responses.
- Treat `src/app/config.py` as the configuration source of truth and preserve process-environment precedence.

## Verification

- `cd apps/backend && uv run pytest`
- `cd apps/backend && uv run pyright`
- `cd apps/backend && uv run ruff check`
