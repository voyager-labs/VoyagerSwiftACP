# Output Template

Use one of the templates below for normal outputs.

## Candidate List (default)

```text
1. summary

- Staged changes item 1
- Staged changes item 2
...
- Staged changes item N

2. summary

- Staged changes item 1
- Staged changes item 2
...
- Staged changes item N

3. summary

- Staged changes item 1
- Staged changes item 2
...
- Staged changes item N
```

Rules:

- Generate exactly 3 candidates.
- Subject is a plain summary sentence — no type prefix, no scope, no `:` separator. Use imperative mood, capitalize first letter, no trailing period.
- Subject must represent all staged changes.
- Omit the body when the subject alone is sufficient for the staged change.
- Body is optional. If present, use `- ` for all bullets and cover all meaningful staged changes.
- Do not force a fixed number of bullets.
- Do not add filler bullets to make the body look even, symmetrical, or exhaustive when fewer bullets are enough.
- Do not map bullets to generic categories like intent, impact, or risk when the staged diff contains multiple concrete change items.
- Prefer enumerating concrete staged changes over compressing unrelated changes into a few abstract bullets.

## Final Commit Message (after user selection)

Use one of these two forms:

`summary`

or

```text
summary

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
