# Output Template

Use one of the templates below for normal outputs.

## Candidate List (default)

```text
1. type(scope): summary

- Why this change matters
- Expected impact scope
- Risk or compatibility note

2. type(scope): summary

- Why this change matters
- Expected impact scope
- Risk or compatibility note

3. type(scope): summary

- Why this change matters
- Expected impact scope
- Risk or compatibility note
```

Rules:

- Generate exactly 3 candidates.
- Subject must use Conventional Commit format: `type(scope): summary` or `type: summary`.
- Subject must represent all staged changes.
- Body is optional. If present, keep 1-3 bullets using `- `.

## Final Commit Message (after user selection)

Use one of these two forms:

`type(scope): summary`

or

```text
type(scope): summary

- Intent
- Impact
- Risk
```

Rules:

- Keep the exact selected candidate content.
- Keep a blank line between subject and body when body exists.
