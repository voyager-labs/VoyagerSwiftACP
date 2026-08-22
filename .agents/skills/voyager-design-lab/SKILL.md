---
name: voyager-design-lab
description: "Operate Voyager's React Storybook Design Lab as an evidence-backed File Manager review surface, including native macOS parity claims and current/candidate design variations. Use when adding, changing, comparing, reviewing, or retiring apps/storybook stories, File Manager visual states, component taxonomy, fixtures, token mappings, layout proposals, component placement proposals, or design-lab handoff evidence. Triggers on: Design Lab, Storybook state, design version, current, candidate, material proposal, layout candidate, File Manager illustration, native parity, visual QA, AppKit, SwiftUI, Tahoe, Sequoia, component catalog, workflow prototype, story taxonomy."
compatibility: opencode
metadata:
    workflow: design-lab
---

# Voyager Design Lab

Storybook is an inspectable review surface, not product or native-runtime truth.

## Use with

- Load the generic `storybook` skill when authoring or editing CSF stories.
- Use `voyager-dev` for native macOS implementation changes; this skill never authorizes them.

## Conditional references

| Situation                                                                                        | Read                                         | Do not read when                                                     |
| ------------------------------------------------------------------------------------------------ | -------------------------------------------- | -------------------------------------------------------------------- |
| Story placement, root consumer, workflow proposal, or retirement                                 | `references/authority-and-state-contract.md` | Editing an existing isolated atom with unchanged ownership           |
| SwiftUI/AppKit source, screenshot, Tahoe/Sequoia, material, geometry, or token claim             | `references/native-evidence-contract.md`     | Product behavior has no native-visual claim                          |
| File Manager control icon, navigation glyph, or system symbol                                    | `references/sf-symbol-contract.md`           | The visual is a file thumbnail, preview, or other non-symbol content |
| Translating structure, state, geometry, or style between native and Storybook (either direction) | `references/translation-workflow.md`         | Editing an existing isolated atom with no native correspondence      |
| Comparing current UI with style, component, placement, or layout candidates in one working tree  | `references/design-version-workflow.md`      | A single accepted implementation has no active design alternative    |
| Implementation review, validation, or handoff                                                    | `references/review-and-verification.md`      | Planning-only work with no changed state                             |

## Workflow

1. **Establish authority.** Read `../../../apps/storybook/DESIGN.md` (workspace workflow owner), `../../../apps/storybook/surface-registry.ts` (registry lifecycle), `../../../apps/storybook/.storybook/main.ts`, and the affected package's `DESIGN.md`. For add/move/retire work, read the registry and the workspace root DESIGN document. Read canonical product docs for product intent; use Linear only for scope and ownership.
2. **Classify the state.** It is either root File Manager composition, a reusable specimen, or an independent experiment. Apply the state contract before adding a workflow.
3. **Route alternatives.** When more than one design is active, load the design-version workflow and derive each candidate from the closest current variation instead of cloning the state matrix.
4. **Gate parity claims.** Classify native evidence, require a deterministic fixture for runtime-dependent rendering, and map roles through `--macos-*` then `--fm-*`.
5. **Implement boundedly.** Fixtures are deterministic and local: no network, clock, random data, or simulated production backend. A clickable control proves only the web prototype unless an executable test proves more.
6. **Verify and hand off.** Run the matching checks and record only the evidence actually obtained. Retire a state when its review question is resolved and it has no root consumer.

## Storybook browser verification

Browser verification is conditional, change-scoped evidence. Use it only when the acceptance criteria make a visual, responsive, accessibility, or interaction claim. Do not turn every Storybook edit into a browser run, screenshot, native build/test, full application E2E, or exhaustive story × viewport × state matrix.

- Inspect only affected stories and representative changed states after implementation convergence; do not capture intermediate edits.
- Use one viewport by default. Add viewports, schemes, or states only when the acceptance criteria require them.
- Use the `agent-browser` CLI for the required Storybook accessibility, interaction, or screenshot claim. Do not substitute Playwright MCP for this project workflow.
- If browser evidence is required and `agent-browser` is unavailable, report the verification as blocked instead of silently changing tools. If browser evidence is not required, do not run it and report it as not applicable.
- Use a fresh named session, wait for `networkidle`, capture `snapshot -i --json`, exercise the target interaction, and save a screenshot after the final state.
- Record the Storybook URL, session, viewport, state, interaction result, and screenshot path when browser evidence is collected.
- A Storybook browser capture proves only the inspected Storybook presentation or interaction. It does not prove native runtime, reducer/backend/auth/filesystem behavior, or production E2E.
- If a server is intentionally started for verification, prove readiness with `lsof` and `curl`, then stop it and re-check the port.

Native evidence and full application E2E are opt-in for explicit named runtime claims. OMO and Hephaestus handoffs must state changed paths, affected stories, required evidence, out-of-scope checks, and the stop condition; do not infer a larger verification matrix from a generic visual-change instruction. Do not introduce named verification profiles for this workflow.

## Common mistakes

- Porting every historical prototype merely to claim migration completeness.
- Calling a static Storybook rendering a production flow or native behavior.
- Resolving material, geometry, or interactive parity from source or screenshot pixels without a deterministic fixture.
- Using a screenshot hex value directly in component CSS.
- Leaving an isolated workflow after its review question has been decided.
- Encoding appearance, OS baseline, geometry, or UI state into candidate IDs and duplicating their stories.
- Treating a successful build as visual-regression, accessibility, or native-parity proof.
- Adding a surface to the catalog without a registry entry and an app-owned story root — appearance in Storybook follows the app catalog (`src/<Surface>/` per `surface-registry.ts`), not a colocated `*.stories.tsx` beside package source.
