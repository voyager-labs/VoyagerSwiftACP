# Selection And Commit Workflow

## Selection

1. Always present full candidate previews in plain text first (subject and optional body for all 3 candidates).
2. After previews, prefer an interactive selection component (if the runtime supports structured choice input).
3. In both interactive and text fallback mode, present exactly 4 options:

- `1`
- `2`
- `3`
- `Reroll`

4. Use short option labels in UI. Do not rely on UI option descriptions to show full commit bodies.
5. If interactive selection is unavailable, prompt with `Choose 1, 2, 3, or Reroll (R/r)`.
6. Accept only `1`, `2`, `3`, `Reroll`, `reroll`, `R`, or `r` as valid inputs.
7. If input is ambiguous, respond with `Please choose 1, 2, 3, or Reroll (R/r).` and wait.
8. If user selects any reroll alias (`Reroll`, `reroll`, `R`, `r`), generate a new set of 3 candidates from the current staged changes, then repeat the selection step.

## Commit Execution

1. Do not commit unless the user explicitly requests commit or selects candidate `1`, `2`, or `3`.
2. If selected message is subject-only, run:

```bash
git commit -m "<selected-subject>"
```

3. If selected message includes body, use one of:

```bash
git commit -m "<selected-subject>" -m "<body-line-1>\n<body-line-2>"
```

or a temporary file with `git commit -F`.

4. If commit fails, return a short error summary and request retry input.
5. On success, report only the commit hash.
