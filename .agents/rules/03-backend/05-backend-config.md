---
globs: apps/backend/**/*.py
description: 'Backend configuration policy — environment variable-based loading and secrets management'
---

# Backend Configuration Policy

## Configuration System

- **Environment variable-based**: Direct loading from `.env` files and process environment
- **Config module**: [apps/backend/src/app/config.py](mdc:apps/backend/src/app/config.py)
- **Data structure**: `VoyagerConfig` dataclass mirroring `.env` file structure

## Environment Variable Loading Order

Priority (highest first):

1. **Process environment variables** (always takes precedence)
2. **`.env.{BACKEND_MODE}`** (e.g., `.env.source`, `.env.bundled`)
3. **`.env.{APP_ENV}`** (e.g., `.env.dev`, `.env.prod`)

Loading uses `python-dotenv` with `override=False`, so earlier values are preserved.

## Environment Files

| File | Purpose | Git Tracked |
|------|---------|-------------|
| `.env.dev` | Local development secrets | No (gitignored) |
| `.env.prod` | Production template (no secrets) | Yes |
| `.env.source` | Source mode backend | Yes |
| `.env.bundled` | Bundled mode backend | No (gitignored) |

## Configuration Access

### VoyagerConfig (Singleton)

```python
from app.config import load_config, get_db_config

cfg = load_config()  # Returns singleton VoyagerConfig instance

# Direct field access (flat structure)
app_name = cfg.app_name
app_env = cfg.app_env
llm_provider = cfg.llm_provider

# DB configuration
db_config = get_db_config(cfg)  # Returns DbConfig from infra.db.models
```

### FastAPI Integration

```python
from app.config import load_config, get_db_config

@asynccontextmanager
async def lifespan(app: FastAPI):
    cfg = load_config()
    app.state.config = cfg

    # DB initialization
    db_config = get_db_config(cfg)
    initialize_sqlite_db(db_config)

    yield
```

## Environment Variable Reference

### App Settings

| Variable | VoyagerConfig Field | Description |
|----------|---------------------|-------------|
| `PUBLIC_APP_NAME` | `app_name` | Application name |
| `APP_ENV` | `app_env` | Environment (`dev`/`prod`) |
| `PUBLIC_LOG_LEVEL` | `log_level` | Logging level |

### Backend Settings

| Variable | VoyagerConfig Field | Description |
|----------|---------------------|-------------|
| `PUBLIC_BACKEND_HOST` | `backend_host` | Server host |
| `PUBLIC_BACKEND_PORT` | `backend_port` | Server port (0 = dynamic) |
| `PUBLIC_BACKEND_PROCESS_NAME` | `backend_process_name` | Process title |

### SQLite Settings

| Variable | VoyagerConfig Field | Description |
|----------|---------------------|-------------|
| `PUBLIC_SQLITE_PROTOCOL` | `sqlite_protocol` | DB protocol (`sqlite:///`) |
| `PUBLIC_SQLITE_ECHO` | `sqlite_echo` | SQL logging (bool) |
| `PUBLIC_SQLITE_CHECK_SAME_THREAD` | `sqlite_check_same_thread` | Thread safety (bool) |
| `PUBLIC_SQLITE_FILE_LOCATION` | `sqlite_file_location` | DB directory path |
| `PUBLIC_SQLITE_FILE_NAME` | `sqlite_file_name` | DB filename |

### Gateway/Web Settings

| Variable | VoyagerConfig Field | Description |
|----------|---------------------|-------------|
| `PUBLIC_GATEWAY_URL` | `gateway_url` | API gateway URL |
| `PUBLIC_WEB_BASE_URL` | `web_base_url` | Web app base URL |

### Secrets (Environment Only)

| Variable | VoyagerConfig Field | Description |
|----------|---------------------|-------------|
| `OPENAI_API_KEY` | `openai_api_key` | OpenAI API key |
| `ANTHROPIC_API_KEY` | `anthropic_api_key` | Anthropic API key |

## LLM Configuration

LLM settings are currently hardcoded as constants (temporary):

```python
# TODO: gateway 연결 시 삭제
llm_provider: Literal["openai", "ollama", "anthropic"] = "openai"
llm_model: str = "gpt-5-mini-2025-08-07"
llm_temperature: float = 0.3
```

Only API keys are loaded from environment variables.

## Secrets Management

- **Security guidelines**: Follow [04-security-and-secrets.md](/.agents/rules/00-monorepo/04-security-and-secrets.md)
- **Dev secrets**: Store in `.env.dev` (gitignored)
- **Prod secrets**: Inject via process environment or Keychain
- **Never bundle secrets**: Keep secrets out of compiled artifacts

## Adding New Configuration

1. Add environment variable to `.env.example`, `.env.dev`, `.env.prod`
2. Add corresponding field to `VoyagerConfig` dataclass
3. Update `load_config()` to read the new variable
4. Update this documentation
5. Consider impact on data models (see [04-data-modeling-and-schemas.md](/.agents/rules/03-backend/04-data-modeling-and-schemas.md))

## Notes

- See [00-backend-overview.md](/.agents/rules/03-backend/00-backend-overview.md) for backend overview
- See [02-architecture-overview.md](/.agents/rules/00-monorepo/02-architecture-overview.md) for system architecture
- See [05-logging-observability.md](/.agents/rules/00-monorepo/05-logging-observability.md) for logging configuration
- See [01-dev-run-and-env.md](/.agents/rules/00-monorepo/01-dev-run-and-env.md) for development workflow
