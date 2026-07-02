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
- Use the canonical env key names defined by `.env.*` and product/app contracts for runtime URLs (for example, `PUBLIC_WEB_BASE_URL` for public web links).
- Model public web destinations as `PUBLIC_WEB_BASE_URL` plus code-owned route paths unless a product/app contract already defines a separate destination URL key.
- Treat required runtime URL config as an explicit contract: fail closed, surface an error state, or disable the action when the value is missing or invalid.

## Runtime model

- Debug schemes usually run backend in source mode (`uv run dev`).
- Prod schemes may run bundled binary mode.

## Must not

- Duplicate full backend dotenv content inside Swift runtime state.
- Assume fixed backend port.
- Add new `ProcessInfo.processInfo.environment` reads for app config, URL, gateway, web, checkout, pricing, or feature env values.
- Add per-route or per-destination env keys for checkout, pricing, support, or other public web pages when the canonical base URL plus route path is sufficient.
- Add placeholder or synthetic URL fallbacks such as `example.invalid`, localhost, empty strings, or made-up base URLs for required app/web/checkout/pricing/support links.

## Execution steps

1. Identify the canonical base URL key for the destination family before adding or changing URL config.
2. Compose stable public web destinations from the canonical base URL plus a code-owned route path.
3. Introduce a separate destination URL env key only after confirming an existing product/app contract requires route-level configurability.

## Verification

- Validate request/response decoding on changed endpoints.
- Validate bootstrap flow for the touched mode (`source` or `bundled`).
- Search changed Swift files for `ProcessInfo.processInfo.environment`; allow only true process/system metadata or test-harness detection with a local reason.
- Search changed Swift files for new per-route public web env keys and verify they are backed by `.env.*` or product/app contracts.
- Search changed Swift files for placeholder URL fallbacks (`example.invalid`, `neutralBaseURL`, made-up localhost defaults) and verify required URL values use canonical env keys or explicit error handling.
