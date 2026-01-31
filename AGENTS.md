# Repository Guidelines

Before making changes, review the additional guardrails in `.cursor/rules`.

## Agent Workflow & Language

- Draft a short execution plan prior to edits as outlined in `.cursor/rules/99-agent/00-agent-mode.mdc`.
- Keep user-facing conversation in Korean while code, identifiers, and commands remain in English.
- Write new code comments in Korean and keep repository documents/commits aligned with local conventions.

## Project Structure & Module Organization

- `apps/backend`: FastAPI service with domain modules under `src/{app,core,infra,utils}` and configuration in `src/conf`. SQLite dev artifacts live at the root; keep migrations in Alembic versions once added.
- `apps/macos/Voyager`: macOS Swift workspace. App sources live in `Voyager/`, helper extensions in `VoyagerHelper/`, and test bundles under the `*Tests` directories. Derived build outputs stay inside `Voyager/build`; do not commit them.
- `apps/macos/Voyager`의 Voyager 타깃은 메인 프론트엔드 앱이며 TCA 기반으로 구성되고, 폴더 구조는 FSD(Feature-Sliced Design) 스타일을 차용합니다.
- `docs/`: AI 에이전트용 PRD/아키텍처 문서 인덱스. 문서 추가 시 `docs/index.md`를 갱신하고, 상세 규칙은 `.cursor/rules/`를 SSOT로 유지합니다.
- 공용 스킬(팀 공유)은 `.claude/skills/*/SKILL.md`에 추가합니다. (OpenCode에서 `.claude/skills`를 로드)
  - 범용: `commit-message`, `pr-review`, `bug-triage`, `test-runner`, `changelog`
  - macOS: `macos-tca-fsd-scaffold`, `macos-tca-orchestrator`
- macOS Voyager(FSD + TCA) 구조/의존성 규칙/리듀서 컨벤션(typealias 기반 State/Action 분리, 부모(오케스트레이터)+하위 리듀서 주입 패턴)은 `docs/architecture/macos-app.md`를 기준으로 합니다.
- Place shared documentation at the repo root. New tooling- or platform-specific guides should sit alongside their respective app directories.

## Build, Test, and Development Commands

- Backend setup: `cd apps/backend && uv sync && uv run pre-commit install` installs dependencies and hooks.
- Backend dev server: `uv run dev` launches FastAPI with auto-reload; `uv run prod` mirrors production settings.
- macOS app: open with `xed apps/macos/Voyager/Voyager.xcworkspace` for GUI work, or build via `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug`.
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
