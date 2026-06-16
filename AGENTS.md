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
- `docs/canonical/` 내부 파일(콘텐츠)은 사용자가 요청하면 자유롭게 읽고 편집할 수 있다.
- 단, **submodule pointer**(부모 레포에서 `docs/canonical`이 가리키는 커밋 참조)는 사용자가 명시적으로 inspect/update/reset/restore를 요청하지 않는 한 절대 변경하지 않는다.
- 관련 없는 작업 중 `git status`에 submodule pointer dirty가 보여도 추적하거나 정리하지 않는다.

## Plan quality conventions

Plans under `.sisyphus/plans/` must follow the quality contract in `.agents/rules/99-agent/11-plan-quality-contract.md`. Every implementation plan includes TDD evidence policy, test ownership convention, and commit workflow references. Agents that write or review plans must load and apply this rule.

## Destructive operation safety

Agents must never run destructive git or filesystem operations (`git checkout -- .`, `git clean`, `git reset --hard`, `rm -rf`, etc.) without first asking the user for explicit confirmation, even when tool permissions allow it. See `.agents/rules/99-agent/12-destructive-operation-confirmation.md`.

## Commit attribution

- Agents must **never** add `Co-authored-by: Sisyphus`, `Co-authored-by: Sisyphus <...>`, `Ultraworked with Sisyphus`, or any similar AI/Sisyphus co-author trailer to commit messages.
- This applies to commit subjects, bodies, and footers alike.
- The only exception is when the user explicitly requests such a trailer.

## Lint suppression policy

Agents must never silence lint/type warnings with inline suppression comments or pragma directives as a per-edit workaround. This applies to every language and toolchain in the repo.

- Forbidden as workarounds: `swiftlint:disable`, `swiftlint:disable:this`, `swiftlint:disable:next`, file-level `swiftlint:disable` blocks, `# type: ignore`, `# noqa`, `# pylint: disable=`, `@SuppressWarnings`, and equivalents.
- Required response to a lint warning: fix the underlying code (restructure, extract helper, use safer API, shorten line). The warning is the signal.
- Escalate when the fix is out of scope: report rule name, file, line, and reason to the user. Never suppress silently.
- Project-wide configuration changes in `.swiftlint.yml`, `pyproject.toml`, `ruff.toml`, etc. are policy decisions, not per-edit workarounds. They require explicit user approval with rationale before applying — never bundle them into an unrelated fix.
- See `.agents/rules/30-macos/00-macos-rules.md` (Lint-disable policy section) for the Swift-specific enforcement of this rule.

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
