---
alwaysApply: true
description: "Commit and PR rules for this repository."
schemaVersion: 2
---

# Commit and PR Rules

## Outcome

- Use Conventional Commits: `<type>(<scope>): <subject>`.
- Keep subject concise.
- When the subject is written in English, keep it imperative.
- When the subject or commit-message body bullets are written in Korean, end them as noun phrases rather than verb-final sentences.
- In Korean, avoid endings like `수정한다`, `이전한다`, `정리한다`; prefer noun-phrase endings like `수정`, `이전`, `정리`.
- Use scope when helpful: `backend`, `macos`, `docs`, `infra`.
- Keep commits logically atomic.
- In PRs, include intent, scope, risks, validation, and rollback notes.
- Never add `Co-authored-by: Sisyphus`, `Co-authored-by: Sisyphus <...>`, `Ultraworked with Sisyphus`, or any similar AI/Sisyphus co-author trailer to commit messages, including subjects, bodies, and footers, unless the user explicitly requests that trailer.

## Default Actions

- Apply this policy when the user requests commit or PR work.
- Use the preferred types and examples below when selecting a commit subject.

## Decision Rules

- Keep a requested commit scope separate when backend and macOS changes are unrelated.

## Stop Conditions

- Commit without explicit user request.
- Mix unrelated backend and macOS changes in one commit.
- Rewrite published history unless explicitly requested.

## Verification

- Before committing, confirm the user explicitly requested a commit, the commit is logically atomic, and no prohibited AI/Sisyphus attribution appears in its subject, body, or footer.
- Before creating a PR, confirm its description includes intent, scope, risks, validation, and rollback notes.

### Preferred types

- `feat`, `fix`, `refactor`, `ui`, `docs`, `test`, `chore`, `ci`, `build`.

### Example subjects

- `feat(backend): add asset ingestion endpoint`
- `fix(macos): handle empty search response`
- `docs: simplify agent rule architecture`
- `fix(macos): 파일매니저 툴바 hover 표시 복구`
