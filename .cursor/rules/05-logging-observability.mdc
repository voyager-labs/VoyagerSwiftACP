---
alwaysApply: true
description: 'Logging, observability, and redaction guidance across the monorepo'
---

# Logging & Observability

## Backend (FastAPI)

- Primary logger: `uvicorn.error` for startup banner and runtime warnings/errors
- Levels: `INFO` for lifecycle, `WARNING` for recoverable events, `ERROR` for failures
- Never log API keys, tokens, or `.env` contents; only non-sensitive metadata
- Startup banner example: `env=dev db_rev=...` (see [apps/backend/src/app/main.py](mdc:apps/backend/src/app/main.py))

## Frontend (macOS SwiftUI)

- Helper forwards backend stderr to its own stderr (Xcode Console / 시스템 로그)
- (선택) 로그 파일 경로는 `VOYAGER_LOG_FILE`로 설정할 수 있도록 확장 가능
- 로그 파일을 repo에 커밋하지 말고, 커지면 수동 로테이션/삭제

## PII Redaction

- Never log secrets or tokens; redact with `***` when unavoidable
- Avoid logging full file paths or user-identifying data
- Prefer anonymized summaries over raw data

## Future Observability

- Consider structured logging and health checks (`/healthz`) when needed
- Metrics: request duration, failure counts, background job timings
