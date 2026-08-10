# Review And Verification

Read this reference after a Storybook implementation or when reporting a review result. It does not prove native behavior, browser accessibility, or visual regression by itself.

## Verification routes

| Change | Minimum evidence | Expand when |
| --- | --- | --- |
| Story/component fixture only | `cd apps/storybook && pnpm --filter @voyager-labs/file-manager-illustration typecheck` | The change affects shared package output or Storybook discovery |
| Package API, root composition, tokens, or catalog | `cd apps/storybook && pnpm check && pnpm build-storybook` | Static catalog or public-contract assumptions changed |
| Static contract | After a successful Storybook build: `pnpm --filter @voyager-labs/file-manager-illustration verify:contract` | The script's runtime, export, CSS, or catalog assertions cover the change |
| Native parity claim | Relevant route above plus the evidence matrix from `native-evidence-contract.md` | A runtime unknown requires a capture or fixture |

If an unrelated working-tree failure blocks a command, name its path and diagnostics. Do not modify unrelated work merely to obtain a green result.

## Review record

For a material state, leave a concise record in the issue, PR, or the existing native-evidence document:

```md
- Decision: what the story demonstrates or what was retired.
- Authority: canonical path, native provenance, or `experiment`.
- Checked: story state and commands that actually passed.
- Unknown/deviation: unobserved runtime state or intentional difference.
- Follow-up: owner/issue, or `none`.
```

Do not create a second source of truth. Link the canonical or evidence record instead of duplicating requirements.
