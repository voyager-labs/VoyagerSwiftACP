---
alwaysApply: true
description: 'Routing rules: which domain rules to load by path/task.'
---

# Rule Routing

## Applies when
- At task start, before editing.

## Routing map
- If touching `apps/backend/**`:
  - Load `20-backend/00-backend-rules.md`
  - Load `20-backend/01-api-and-schemas.md`
  - Load `20-backend/02-migrations-and-config.md` when config/db changes.
- If touching `apps/macos/**`:
  - Load `30-macos/00-macos-rules.md`
  - Load `30-macos/01-http-and-env.md` for network/env/bootstrap work.
- If touching both backend and macOS:
  - Load both backend and macOS domain rules.
- If docs-only:
  - Load `99-agent/00-rule-authoring.md` when editing `.agents/rules/**`.

## Must
- Load only relevant rules to reduce context bloat.
- Escalate to broader rule sets only when scope expands.

## Must not
- Blindly load every rule file for small localized tasks.
