---
alwaysApply: true
description: 'Commit and PR rules for this repository.'
---

# Commit and PR Rules

## Applies when
- User requests commit or PR work.

## Must
- Use Conventional Commits: `<type>(<scope>): <subject>`.
- Keep subject concise.
- When the subject is written in English, keep it imperative.
- When the subject or commit-message body bullets are written in Korean, end them as noun phrases rather than verb-final sentences.
- In Korean, avoid endings like `수정한다`, `이전한다`, `정리한다`; prefer noun-phrase endings like `수정`, `이전`, `정리`.
- Use scope when helpful: `backend`, `macos`, `docs`, `infra`.
- Keep commits logically atomic.
- In PRs, include intent, scope, risks, validation, and rollback notes.

## Must not
- Commit without explicit user request.
- Mix unrelated backend and macOS changes in one commit.
- Rewrite published history unless explicitly requested.

## Preferred types
- `feat`, `fix`, `refactor`, `ui`, `docs`, `test`, `chore`, `ci`, `build`.

## Example subjects
- `feat(backend): add asset ingestion endpoint`
- `fix(macos): handle empty search response`
- `docs: simplify agent rule architecture`
- `fix(macos): 파일매니저 툴바 hover 표시 복구`
