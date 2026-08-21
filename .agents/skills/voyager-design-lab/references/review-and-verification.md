# Review And Verification

Read this reference after a Storybook implementation or when reporting a review result. It does not prove native behavior, browser accessibility, or visual regression by itself.

## Verification routes

Storybook-only package/catalog changes are proven with Storybook evidence. Native evidence is required only for the runtime claims named by `native-evidence-contract.md` (dynamic colors, materials, intrinsic dimensions, modifier order, hover/focus/pressed/disabled/inactive-window visuals).

| Change                                            | Minimum evidence                                                                      | Expand when                                                               |
| ------------------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Story/component fixture only                      | `cd apps/storybook && pnpm --filter <surface-package> typecheck`                      | The change affects shared package output or Storybook discovery           |
| Package API, root composition, tokens, or catalog | `cd apps/storybook && pnpm check && pnpm build-storybook`                             | Static catalog or public-contract assumptions changed                     |
| Static contract                                   | After a successful Storybook build: `pnpm --filter <surface-package> verify:contract` | The script's runtime, export, CSS, or catalog assertions cover the change |
| Native parity claim                               | Relevant route above plus the evidence matrix from `native-evidence-contract.md`      | A runtime unknown requires a capture or fixture                           |

`<surface-package>` is the package owning the changed surface (e.g. `@voyager-labs/file-manager-illustration`, `@voyager-labs/settings-illustration`). A registry or catalog change (adding/moving/retiring a surface) is proven by the registry-driven discovery check (`pnpm check` + `build-storybook`) and does not need native evidence unless a runtime claim is made.

If an unrelated working-tree failure blocks a command, name its path and diagnostics. Do not modify unrelated work merely to obtain a green result.

## Browser boundary and stop conditions

Browser evidence is conditional on an explicit visual, responsive, accessibility, or interaction claim. Collect it after implementation convergence and inspect only affected stories and representative changed states. Use one viewport by default; add viewports, schemes, or states only when the acceptance criteria require them.

A Storybook browser capture proves only the inspected Storybook presentation or interaction. It does not prove native runtime, reducer/backend/auth/filesystem behavior, or production E2E. Native evidence and full application E2E are opt-in for named runtime claims, not default consequences of a Storybook change.

If browser verification is intentionally run, prove readiness with `lsof` and `curl`, then stop the server and re-check the port. If the acceptance criteria do not require browser or native evidence, stop after the focused checks and record those evidence classes as not applicable. OMO and Hephaestus handoffs must state the required evidence, out-of-scope checks, and stop condition; do not introduce named verification profiles.

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
