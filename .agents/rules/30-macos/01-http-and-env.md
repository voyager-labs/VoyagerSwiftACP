---
globs: apps/macos/**/*.swift
description: 'HTTP client, backend bootstrap, and environment handling rules.'
---

# macOS HTTP and Environment

## Applies when
- Editing API clients, helper bootstrap, or env resolution in macOS app/helper.

## Must
- Derive backend base URL from runtime host/port (`PUBLIC_BACKEND_HOST` + assigned port).
- Avoid hardcoded localhost URLs.
- Support request cancellation for long-running effects.
- Keep retry behavior short and targeted for transient failures.
- Keep backend launch env minimal (`APP_ENV`, `BACKEND_MODE`, `PATH` when needed).

## Runtime model
- Debug schemes usually run backend in source mode (`uv run dev`).
- Prod schemes may run bundled binary mode.

## Must not
- Duplicate full backend dotenv content inside Swift runtime state.
- Assume fixed backend port.

## Verification
- Validate request/response decoding on changed endpoints.
- Validate bootstrap flow for the touched mode (`source` or `bundled`).
