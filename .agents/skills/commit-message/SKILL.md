---
name: commit-message
description: Generate exactly 3 Conventional Commit candidates from currently staged Git changes, present them as a numbered list, explain each candidate briefly, collect user selection with an interactive option picker when available (fallback to text), support a `Reroll` option for new candidates, and execute `git commit` with the selected message. Use for `$commit-message`, commit-message drafting requests, or when the user wants message options before committing.
compatibility: opencode
metadata:
    workflow: git
    output: commit-message
---

# Commit Message Candidate Generator

## Purpose

Generate 3 commit-message candidates from staged changes, ask the user to pick one (or reroll), and commit using the selected candidate.

## Commit Type and Scope Policy

- `feat`, `fix`, `refactor`, `ui`, and `test` should include a scope.
- `docs`, `ci`, `build`, `chore`, and `agent` may omit scope unless a narrower owner materially improves clarity.
- Use the clearest owning scope for scoped types.
    - Voyager macOS: `helper`, `main-app` only for `Voyager/01_App`, `pages/<slice>`, `widgets/<slice>`, `features/<slice>`, `entities/<slice>`, `shared`
    - Other areas: `backend`
- Example scoped subjects: `fix(helper): ...`, `feat(main-app): ...`, `refactor(features/entry-operations): ...`, `fix(pages/file-manager): ...`, `feat(backend): ...`
- Example scope-less subjects: `docs: ...`, `ci: ...`, `build: ...`, `chore: ...`, `agent: ...`

## Hard Rules

- **Ground Truth**: Use ONLY staged changes. NEVER mention unstaged changes.
- **Fresh Context**: Always run the script to gather the latest index state on every invocation. Do not reuse past outputs.
- **Language**: Keep all skill instructions and responses in English unless the user explicitly requests another language for output content.
- **Output Mode**: Default behavior is presenting 3 candidates. Returning only one final message is allowed only after the user has selected a candidate.
- **Selection UX**: Prefer interactive selection components when available. Always include the fourth option: `Reroll`.
- **Preview First**: Always print full candidate previews (subject and body) in normal text before opening any selection UI.
- **Follow Templates**: Use `references/output-template.md`, `references/response-template.md`, and `references/selection-and-commit.md`.
- **Comprehensive Subject**: If multiple files are staged, the subject MUST cover the intent of ALL staged changes. Do not write a subject that only covers one file.
- **Empty State**: If no files are staged, do not hallucinate a message. Inform the user to stage files.
- **Body Optionality**: Omit the body when the staged change is small enough and the subject already communicates the change clearly.
- **Korean Phrasing**: When the subject or body bullets are written in Korean, end them as noun phrases, not verb-final sentences.
- **Korean Ending Examples**: Avoid endings like `수정한다`, `이전한다`, `정리한다`; prefer `수정`, `이전`, `정리`.
- **Bullet Format**: If adding a body, use `- ` for all bullet points.
- **No Bullet Padding**: Never add filler bullets just to make the message look balanced or complete. Use only as many bullets as the staged changes actually need.
- **No Secrets**: Never include API keys, tokens, or PII in the commit message.

## Workflow

1. **Collect Staged Context**
    - Run the script to gather the latest index state:

    ```bash
    python3 .claude/skills/commit-message/scripts/collect_staged_context.py
    ```

    - If the patch is too long, reduce lines to avoid token overflow:

    ```bash
    python3 .claude/skills/commit-message/scripts/collect_staged_context.py --head-lines 600 --tail-lines 600
    ```

2. **Draft Message Candidates**
    - Draft **exactly 3 candidates**.
    - Apply the `Commit Type and Scope Policy` section above.
    - Follow formatting and quality rules in `references/output-template.md`.
    - Use exception handling rules from `references/response-template.md`.
    - Show all candidate details in plain text before asking for selection.

3. **User Selection**
    - Follow selection prompt and validation in `references/selection-and-commit.md`.

4. **Commit**
    - Follow commit execution and reporting rules in `references/selection-and-commit.md`.

## Bundled Resources

- `scripts/collect_staged_context.py`: Extracts staged files, statistics, branch/issue hints, and recent commit style in one go.
- `references/output-template.md`: Candidate and final-message output format.
- `references/response-template.md`: Exception and short operational responses.
- `references/selection-and-commit.md`: Candidate selection validation and commit execution protocol.
