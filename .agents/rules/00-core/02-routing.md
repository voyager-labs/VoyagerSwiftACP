---
description: "Routing rules: which domain rules to load by path/task."
alwaysApply: true
schemaVersion: 2
---

# Rule Routing

## Outcome

- Load only relevant rules to reduce context bloat.
- Escalate to broader rule sets only when scope expands.

## Default Actions

1. At task start, identify changed or intended paths before selecting domain rules.
2. Apply the routing map below to load the smallest complete rule set for those paths.
3. If scope expands into another path family, load the newly relevant rules before editing further.

## Decision Rules

- If touching `apps/backend/**`:
    - Load `20-backend/00-backend-rules.md`
    - Load `20-backend/01-api-and-schemas.md`
    - Load `20-backend/02-migrations-and-config.md` when config/db changes.
- If touching `apps/macos/**`:
    - Load `30-macos/00-macos-rules.md`
    - Load `30-macos/01-http-and-env.md` for network/env/bootstrap work.
    - If touching Voyager app, package, host, helper, XPC, or macOS test code, load `.agents/skills/voyager-dev/orchestrator/SKILL.md` and `references/voyager-app-workflow.md`:
        - `apps/macos/Voyager/Voyager/**`
        - `apps/macos/Voyager/VoyagerHelper/**`
        - `apps/macos/Voyager/FilterSearchXPC/**`
        - `apps/macos/Voyager/VoyagerTests/**`
        - `apps/macos/Voyager/VoyagerHelperTests/**`
        - `apps/macos/Voyager/VoyagerUITests/**`
        - `apps/macos/Packages/**`
        - `apps/macos/Hosts/**`
    - Load skill `code-tooling` for code navigation, search, build, and diagnostics operations.
- If touching both backend and macOS:
    - Load both backend and macOS domain rules.
- If docs-only:
    - Load `99-agent/00-rule-authoring.md` when editing `.agents/rules/**`.
    - Load `99-agent/02-harness-placement.md` when editing `.agents/skills/**`.

## Stop Conditions

- Blindly load every rule file for small localized tasks.

## Verification

- Confirm every touched path family has a matching domain rule or an explicit reason no domain rule applies.
- Confirm `.agents/rules/**` edits loaded rule-authoring guidance and `.agents/skills/**` edits loaded harness placement guidance.
