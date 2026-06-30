---
description: "HTTP client, backend bootstrap, and environment handling rules."
globs: "apps/macos/**/*.swift"
---

# macOS HTTP and Environment

## Must

- Derive backend base URL from runtime host/port (`PUBLIC_BACKEND_HOST` + assigned port).
- Avoid hardcoded localhost URLs.
- Support request cancellation for long-running effects.
- Keep retry behavior short and targeted for transient failures.
- Keep backend launch env minimal (`APP_ENV`, `BACKEND_MODE`, `PATH` when needed).
- Read Swift runtime app config and URL/env values through `EnvironmentLoader`; reserve direct SwiftDotenv access for environment loader/bootstrap code.

## Runtime model

- Debug schemes usually run backend in source mode (`uv run dev`).
- Prod schemes may run bundled binary mode.

## Must not

- Duplicate full backend dotenv content inside Swift runtime state.
- Assume fixed backend port.
- Add new `ProcessInfo.processInfo.environment` reads for app config, URL, gateway, web, checkout, pricing, or feature env values.

## Verification

- Validate request/response decoding on changed endpoints.
- Validate bootstrap flow for the touched mode (`source` or `bundled`).
- Search changed Swift files for `ProcessInfo.processInfo.environment`; allow only true process/system metadata or test-harness detection with a local reason.
