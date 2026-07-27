# HTTP and Environment Contract

## Outcome

- Read Swift runtime app config and URL values through `EnvironmentLoader`.
- Resolve remote account and access requests from `PUBLIC_GATEWAY_URL`.
- Keep local search and indexing on VoyagerHelper and FilterSearchXPC; they are not HTTP bootstrap targets.
- Apply cancellation and short, targeted retry behavior only to actual remote requests.

## Runtime Model

- VoyagerHelper owns folder access and file-change observation.
- FilterSearchXPC owns local Spotlight query execution.
- The remote Gateway owns account and access APIs used by the macOS app.
- The app bundle does not launch a local Python API server.

## Stop Conditions

- Do not hardcode localhost or assign a local Python API server port.
- Do not add source or bundled local Python API server launch modes.
- Do not add `ProcessInfo.processInfo.environment` reads for app config, URL, gateway, web, checkout, pricing, or feature environment values.
- Do not duplicate full dotenv content inside Swift runtime state; reserve direct SwiftDotenv access for environment loader or bootstrap code.

## Verification

- Validate request and response decoding for changed remote endpoints.
- Validate Gateway URL resolution through `EnvironmentLoader`.
- Validate VoyagerHelper and FilterSearchXPC build wiring when their boundary changes.
- Search changed Swift files for `ProcessInfo.processInfo.environment`; allow only true process/system metadata or test-harness detection with a local reason.
