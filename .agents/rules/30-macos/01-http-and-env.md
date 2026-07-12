---
description: "HTTP client, backend bootstrap, and environment handling rules."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# macOS HTTP and Environment

## Outcome

- Derive backend base URL from runtime host/port (`PUBLIC_BACKEND_HOST` + assigned port).
- Avoid hardcoded localhost URLs.
- Support request cancellation for long-running effects.
- Keep retry behavior short and targeted for transient failures.
- Keep backend launch env minimal (`APP_ENV`, `BACKEND_MODE`, `PATH` when needed).

## Default Actions

- Support request cancellation for long-running effects.
- Keep retry behavior short and targeted for transient failures.
- Keep backend launch env minimal (`APP_ENV`, `BACKEND_MODE`, `PATH` when needed).

## Decision Rules

- Debug schemes usually run backend in source mode (`uv run dev`).
- Prod schemes may run bundled binary mode.

## Stop Conditions

- Debug schemes usually run backend in source mode (`uv run dev`).
- Prod schemes may run bundled binary mode.

## Verification

- Validate request/response decoding on changed endpoints.
- Validate bootstrap flow for the touched mode (`source` or `bundled`).
