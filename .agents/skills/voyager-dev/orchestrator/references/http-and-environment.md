# HTTP and Environment Contract

## Outcome

- Read Swift runtime app config and URL values through `EnvironmentLoader`.
- Resolve remote account and access requests from `PUBLIC_GATEWAY_URL`.
- Keep local search and indexing on VoyagerHelper and FilterSearchXPC; they are not HTTP bootstrap targets.
- Apply cancellation and short, targeted retry behavior only to actual remote requests.
- Treat `ProcessInfo.processInfo.environment` as closed by default in production Swift.

## Runtime Model

- VoyagerHelper owns folder access and file-change observation.
- FilterSearchXPC owns local Spotlight query execution.
- The remote Gateway owns account and access APIs used by the macOS app.
- The app bundle does not launch a local Python API server.

## Process Environment Ownership

- Use `EnvironmentLoader` as the only owner for runtime app config, URLs, and feature configuration.
- Allow direct literal `ProcessInfo` reads only for existing host, scheme, test-harness, or system controls declared in `ALLOWED_PROCESS_INFO_LITERAL_KEYS`.
- Allow a full process-environment snapshot only in adapters declared in `ALLOWED_PROCESS_INFO_SNAPSHOT_FILES`, such as `EnvironmentLoader` or a subprocess environment filter.
- Reject dynamic `ProcessInfo.processInfo.environment[key]` access because it bypasses key ownership review.
- Do not add a direct `ProcessInfo` read as a shortcut around `EnvironmentLoader` or dotenv ownership.
- When a new process-only control is unavoidable, update the validator manifest and add a regression test in the same change with a local reason for the ownership exception.
- Validate environment consumers rather than maintaining a global allowlist of values that launch tools may inject.

## Stop Conditions

- Do not hardcode localhost or assign a local Python API server port.
- Do not add source or bundled local Python API server launch modes.
- Do not add `ProcessInfo.processInfo.environment` reads for app config, URL, gateway, web, checkout, pricing, or feature environment values.
- Do not add a new literal key, dynamic subscript, or full environment snapshot without an explicit validator ownership entry.
- Do not duplicate full dotenv content inside Swift runtime state; reserve direct SwiftDotenv access for environment loader or bootstrap code.

## Verification

- Validate request and response decoding for changed remote endpoints.
- Validate Gateway URL resolution through `EnvironmentLoader`.
- Validate VoyagerHelper and FilterSearchXPC build wiring when their boundary changes.
- Confirm the app has no local Python API server launch path or deleted backend host/mode setting.
- Run `python3 -m scripts.validate_build_matrix`; it must reject every unmanifested literal key, dynamic subscript, and full environment snapshot.
- Confirm launch surfaces reject tracked dotenv keys and deprecated keys without rejecting unrelated injected values.
