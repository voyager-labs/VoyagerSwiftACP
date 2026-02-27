---
alwaysApply: true
description: 'Monorepo architecture overview: SwiftUI frontend + FastAPI backend integration'
---

# Architecture Overview (Monorepo High-level)

This document provides a high-level view of the Voyager monorepo architecture, covering both frontend and backend components and their integration.

## System Overview

Voyager is a macOS application that combines local file operations with AI-powered search capabilities. The system consists of:

- **Frontend**: macOS SwiftUI app with TCA (The Composable Architecture)
- **Backend**: Python FastAPI service with AI/ML capabilities
- **Integration**: Frontend manages backend lifecycle and communicates via HTTP

## Frontend Architecture (SwiftUI + TCA)

See [00-frontend-overview.md](/.agents/rules/01-macos-voyager/00-frontend-overview.md) for detailed frontend structure and components.

## Backend Architecture (FastAPI + Python)

See [00-backend-overview.md](/.agents/rules/03-backend/00-backend-overview.md) for detailed backend structure and entry points.

## Integration & Communication

### Backend Bootstrap
1. Frontend launches backend process via helper classes
2. Backend starts with appropriate environment (`dev`/`prod`)
3. Frontend derives API base URL from environment configuration
4. Health checks ensure backend readiness before API calls

### Data Flow
1. **User Actions**: SwiftUI UI interactions trigger TCA actions
2. **Local Operations**: File system operations handled by frontend clients
3. **API Calls**: HTTP requests to backend for AI/ML processing
4. **State Updates**: Backend responses update frontend state via TCA reducers

## Cross-cutting Concerns

### Configuration Management
- **Frontend**: Swift-dotenv for environment variables, `.env.{dev|prod}` at repo root (또는 번들 리소스)
- **Backend**: Environment variable-based configuration with `.env` file support
- **Shared**: Common environment keys for integration (`PUBLIC_BACKEND_HOST`, `PUBLIC_BACKEND_PORT`, `APP_ENV`)

### Error Handling
- See [03-error-handling-policy.md](/.agents/rules/00-monorepo/03-error-handling-policy.md) for detailed error handling guidelines
- **Frontend**: TCA-based error state management with user-friendly messages
- **Backend**: Structured error responses with appropriate HTTP status codes
- **Integration**: Network error mapping and retry strategies

### Security & Secrets
- See [04-security-and-secrets.md](/.agents/rules/00-monorepo/04-security-and-secrets.md) for detailed security guidelines
- **Shared**: No secrets in logs, metadata-only startup banners

### Logging & Observability
- See [05-logging-observability.md](/.agents/rules/00-monorepo/05-logging-observability.md) for detailed guidelines
- **Frontend**: Backend process logging to configured file paths
- **Backend**: Structured logging with PII redaction

## Development Workflow

### Local Development
- **Backend**: `uv run dev` for fast refresh with `APP_ENV=dev`
- **Frontend**: Xcode workspace or Cursor/VSCode with Sweetpad extension
- **Integration**: Helper classes manage backend lifecycle automatically

### Environment Coordination
- Shared `.env` file at repository root
- Environment variables bridge frontend and backend configuration
- Consistent naming conventions for integration keys

## Future Extensions

- **AI/ML Pipeline**: Embeddings, vector search, LLM integration
- **Database**: SQLite metadata store with Alembic migrations
- **Vector Store**: Planned integration for semantic search
- **Module Rules**: Component-specific rules as architecture stabilizes
