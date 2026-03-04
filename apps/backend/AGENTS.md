# Agent Instructions (Backend)

Scope: `apps/backend/**`

- Load core rules first: `../../.agents/rules/00-core/00-execution-contract.md`
- Always follow backend rules: `../../.agents/rules/20-backend/00-backend-rules.md`
- For API/schema changes: `../../.agents/rules/20-backend/01-api-and-schemas.md`
- For DB/config changes: `../../.agents/rules/20-backend/02-migrations-and-config.md`
- Required verification: `cd apps/backend && uv run pytest`
