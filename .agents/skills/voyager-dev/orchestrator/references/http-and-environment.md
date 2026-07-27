# HTTP and Environment Contract

## Outcome

- Derive the backend base URL from the runtime host and assigned port (`PUBLIC_BACKEND_HOST` plus the assigned port).
- Avoid hardcoded localhost URLs.
- Support request cancellation for long-running effects.
- Keep retry behavior short and targeted for transient failures.
- Keep backend launch environment minimal (`APP_ENV`, `BACKEND_MODE`, and `PATH` when needed).
- Read Swift runtime app config and URL/environment values through `EnvironmentLoader`; reserve direct SwiftDotenv access for environment loader or bootstrap code.
- Treat `ProcessInfo.processInfo.environment` as closed by default in production Swift.

## Runtime Model

- Debug schemes usually run the backend in source mode (`uv run dev`).
- Production schemes may run bundled binary mode.

## Process Environment Ownership

- Use `EnvironmentLoader` as the only owner for runtime app config, URLs, and feature configuration.
- Allow direct literal `ProcessInfo` reads only for existing host, scheme, test-harness, or system controls declared in `ALLOWED_PROCESS_INFO_LITERAL_KEYS`.
- Allow a full process-environment snapshot only in adapters declared in `ALLOWED_PROCESS_INFO_SNAPSHOT_FILES`, such as `EnvironmentLoader` or a subprocess environment filter.
- Reject dynamic `ProcessInfo.processInfo.environment[key]` access because it bypasses key ownership review.
- Do not add a direct `ProcessInfo` read as a shortcut around `EnvironmentLoader` or dotenv ownership.
- When a new process-only control is unavoidable, update the validator manifest and add a regression test in the same change with a local reason for the ownership exception.
- Validate environment consumers rather than maintaining a global allowlist of values that launch tools may inject.

## Stop Conditions

- Do not duplicate full backend dotenv content inside Swift runtime state.
- Do not assume a fixed backend port.
- Do not add `ProcessInfo.processInfo.environment` reads for app config, URL, gateway, web, checkout, pricing, or feature environment values.
- Do not add a new literal key, dynamic subscript, or full environment snapshot without an explicit validator ownership entry.

## Verification

- Validate request and response decoding for changed endpoints.
- Validate the bootstrap flow for the touched mode (`source` or `bundled`).
- Run `python3 -m scripts.validate_build_matrix`; it must reject every unmanifested literal key, dynamic subscript, and full environment snapshot.
- Confirm launch surfaces reject tracked dotenv keys and deprecated keys without rejecting unrelated injected values.
