# HTTP and Environment Contract

## Outcome

- Derive the backend base URL from the runtime host and assigned port (`PUBLIC_BACKEND_HOST` plus the assigned port).
- Avoid hardcoded localhost URLs.
- Support request cancellation for long-running effects.
- Keep retry behavior short and targeted for transient failures.
- Keep backend launch environment minimal (`APP_ENV`, `BACKEND_MODE`, and `PATH` when needed).
- Read Swift runtime app config and URL/environment values through `EnvironmentLoader`; reserve direct SwiftDotenv access for environment loader or bootstrap code.

## Runtime Model

- Debug schemes usually run the backend in source mode (`uv run dev`).
- Production schemes may run bundled binary mode.

## Stop Conditions

- Do not duplicate full backend dotenv content inside Swift runtime state.
- Do not assume a fixed backend port.
- Do not add `ProcessInfo.processInfo.environment` reads for app config, URL, gateway, web, checkout, pricing, or feature environment values.

## Verification

- Validate request and response decoding for changed endpoints.
- Validate the bootstrap flow for the touched mode (`source` or `bundled`).
- Search changed Swift files for `ProcessInfo.processInfo.environment`; allow only true process/system metadata or test-harness detection with a local reason.
