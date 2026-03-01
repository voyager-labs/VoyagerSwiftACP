---
alwaysApply: true
description: "Security baseline: secrets, logs, and sensitive data handling."
---

# Safety and Secrets

## Applies when

- All tasks, especially config/logging/release changes.

## Must

- Keep secrets in environment variables only.
- Treat `.env.dev` as local-only and gitignored.
- Keep `.env.prod` secret-free.
- Redact tokens and sensitive values in logs.
- Validate required env vars before use.

## Must not

- Commit `.env`, API keys, DB snapshots, or credentials.
- Print full request payloads containing sensitive data.
- Embed secrets in bundled binaries or resource files.

## Execution steps

1. Check whether changed files touch config, auth, or logging.
2. Confirm secret paths remain ignored and not staged.
3. Confirm logs include metadata only.

## Verification

- Run `git status` and inspect staged files for secret-bearing artifacts.
- Search changed files for obvious secret patterns before finishing.
