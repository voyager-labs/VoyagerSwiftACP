# Agent Instructions

This repository separates agent-facing instructions from human-facing documentation.

- **For AI Agents:** All coding standards, rules, and workflows are located in the `.agents/` directory (specifically `.agents/rules/`).
- **Local Agent Artifacts:** Runtime directories such as `.omx/` and `.sisyphus/` are local-only and must never be staged or committed. See `.agents/rules/99-agent/01-agent-harness-artifacts.md`.
- **For Humans:** Product and architecture documentation is located in `docs/index.md`.
- **Product docs:** `docs/canonical/` — canonical Voyager product documentation (git submodule, `voyager-labs/voyager-documentation`).

## Onboarding

clone 후 스크립트 하나로 개발 환경을 구성한다:

```bash
bash scripts/setup.sh
```

이 스크립트는 mise 설치 → `mise run setup` 실행을 자동 처리한다.

### 수동

```bash
mise run setup
```

### 명령 목록

```bash
mise tasks
```

## Protected local files

- Treat `opencode.json` as a user-managed local file.
- Never automatically reset, revert, or discard changes in `opencode.json`.
- Never include `opencode.json` in commits unless the user explicitly asks for it.

## Commit attribution

- Agents must **never** add `Co-authored-by: Sisyphus`, `Co-authored-by: Sisyphus <...>`, `Ultraworked with Sisyphus`, or any similar AI/Sisyphus co-author trailer to commit messages.
- This applies to commit subjects, bodies, and footers alike.
- The only exception is when the user explicitly requests such a trailer.

## Validation

Run the commands that match your change scope.

### Backend (Python/FastAPI)

```bash
cd apps/backend
uv run pytest          # tests
uv run pyright         # type check
uv run ruff check      # linter
```

### macOS (Voyager)

```bash
mise run macos-build   # Dev build
mise run macos-test    # Dev tests
```

Swift lint/format:
```bash
mise exec -- swiftlint --config apps/macos/.swiftlint.yml apps/macos
mise exec -- swiftformat --config apps/macos/.swiftformat apps/macos --verbose
```

### General

```bash
git diff --check       # whitespace/conflict markers
```

## PR review rules

Codex and other agents read `AGENTS.md`, but PR review policy must stay centralized in Greptile rules.

- For AI-powered PR reviews, read and follow `.greptile/rules.md`.
- Do not duplicate PR review language, severity, noise, architecture, or reuse rules in this file.
