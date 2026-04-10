# Output Template

Use one of the templates below for normal outputs.

## Candidate List (default)

```text
1. type(scope): summary

- Staged changes item 1
- Staged changes item 2
...
- Staged changes item N

2. type(scope): summary

- Staged changes item 1
- Staged changes item 2
...
- Staged changes item N

3. type(scope): summary

- Staged changes item 1
- Staged changes item 2
...
- Staged changes item N
```

Rules:

- Generate exactly 3 candidates.
- Subject must use Conventional Commit format: `type(scope): summary` or `type: summary`.
- Subject must represent all staged changes.
- When the subject is written in Korean, end it as a noun phrase rather than a verb-final sentence.
- Omit the body when the subject alone is sufficient for the staged change.
- Body is optional. If present, use `- ` for all bullets and cover all meaningful staged changes.
- When body bullets are written in Korean, each bullet must also end as a noun phrase rather than a verb-final sentence.
- In Korean, avoid endings like `수정한다`, `이전한다`, `정리한다`; prefer `수정`, `이전`, `정리`.
- Do not force a fixed number of bullets.
- Do not add filler bullets to make the body look even, symmetrical, or exhaustive when fewer bullets are enough.
- Do not map bullets to generic categories like intent, impact, or risk when the staged diff contains multiple concrete change items.
- Prefer enumerating concrete staged changes over compressing unrelated changes into a few abstract bullets.

## Final Commit Message (after user selection)

Use one of these two forms:

`type(scope): summary`

or

```text
type(scope): summary

- Staged changes item 1
- Staged changes item 2
- Staged changes item 3
...
- Staged changes item N
```

Rules:

- Keep the exact selected candidate content.
- Keep a blank line between subject and body when body exists.
- Subject-only output is valid when it already describes the staged change clearly.
- When the selected message is written in Korean, keep both the subject and every bullet in noun-phrase ending form.
