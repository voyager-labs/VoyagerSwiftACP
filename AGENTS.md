# Repository Guidelines

Before making changes, review the additional guardrails in `.cursor/rules`.

## Agent Workflow & Language

- Draft a short execution plan prior to edits as outlined in `.cursor/rules/90-agent-mode.mdc`.
- Keep user-facing conversation in Korean while code, identifiers, and commands remain in English.
- Write new code comments in Korean and keep repository documents/commits aligned with local conventions.

## Project Structure & Module Organization

- `apps/backend`: FastAPI service with domain modules under `src/{app,core,infra,utils}` and configuration in `src/conf`. SQLite dev artifacts live at the root; keep migrations in Alembic versions once added.
- `apps/macos/Voyager`: macOS Swift workspace. App sources live in `Voyager/`, helper extensions in `VoyagerHelper/`, and test bundles under the `*Tests` directories. Derived build outputs stay inside `Voyager/build`; do not commit them.
- Place shared documentation at the repo root. New tooling- or platform-specific guides should sit alongside their respective app directories.

## Build, Test, and Development Commands

- Backend setup: `cd apps/backend && uv sync && uv run pre-commit install` installs dependencies and hooks.
- Backend dev server: `uv run dev` launches FastAPI with auto-reload; `uv run prod` mirrors production settings.
- macOS app: open with `xed apps/macos/Voyager/Voyager.xcodeproj` for GUI work, or build via `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug`.
- macOS tests: `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj` runs unit and UI test bundles headlessly.

## Coding Style & Naming Conventions

- Python: follow Ruff formatting (100-character lines, spaces for indents, double quotes by default). Keep modules typed—Pyright runs in `strict` mode, so prefer explicit type hints.
- Swift: match the default Xcode style (4-space indents, `UpperCamelCase` types, `lowerCamelCase` members). Namespace helper categories under `VoyagerHelper`.
- Configuration files (`*.toml`, `*.yaml`) should remain ordered alphabetically where practical to ease diff review.

## Testing Guidelines

- Backend: no formal suite yet—add pytest-based tests under `apps/backend/tests/` with filenames ending in `_test.py`. Run them using `uv run pytest` once the directory exists. Capture regression cases for every API contract change.
- macOS: keep unit specs in `VoyagerTests` and UI flows in `VoyagerUITests`. Name test methods with intent-driven prefixes (e.g., `testDisplaysSidebar...`). Prefer dependency-injected fakes to hitting live services.
- Document manual QA steps in PR descriptions when automated coverage is absent.

## Commit & Pull Request Guidelines

- Use Conventional Commits (`feat:`, `fix:`, `chore:`, etc.). Scope components (e.g., `feat(backend): add asset ingestion endpoint`) when possible.
- Squash or reorganize commits so each expresses a single logical change. Avoid mixing Swift and Python updates unless tightly coupled.
- Pull requests must outline intent, scope, risk, and validation evidence. Link issues, attach screenshots for UI tweaks, and note rollback steps when touching production paths.

## Security & Configuration Tips

- Never commit `.env`, database snapshots, or API keys. Use masked CI variables and rotate any suspected leaks immediately.
- Review notebooks in `apps/backend/notebooks/` before pushing—strip outputs with `nbstripout` or remove the file if it contains sensitive data.
