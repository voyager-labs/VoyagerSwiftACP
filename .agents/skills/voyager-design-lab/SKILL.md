---
name: voyager-design-lab
description: "Operate Voyager's React Storybook Design Lab as an evidence-backed File Manager review surface, including native macOS parity claims. Use when adding, changing, reviewing, or retiring apps/storybook stories, File Manager visual states, component taxonomy, fixtures, token mappings, or design-lab handoff evidence. Triggers on: Design Lab, Storybook state, File Manager illustration, native parity, visual QA, AppKit, SwiftUI, Tahoe, Sequoia, component catalog, workflow prototype, story taxonomy."
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

| Situation | Read | Do not read when |
| --- | --- | --- |
| Story placement, root consumer, workflow proposal, or retirement | `references/authority-and-state-contract.md` | Editing an existing isolated atom with unchanged ownership |
| SwiftUI/AppKit source, screenshot, Tahoe/Sequoia, material, geometry, or token claim | `references/native-evidence-contract.md` | Product behavior has no native-visual claim |
| Implementation review, validation, or handoff | `references/review-and-verification.md` | Planning-only work with no changed state |

## Workflow

1. **Establish authority.** Read `../../../apps/storybook/package.json`, `../../../apps/storybook/.storybook/main.ts`, and the affected package's `DESIGN.md`. Read canonical product docs for product intent; use Linear only for scope and ownership.
2. **Classify the state.** It is either root File Manager composition, a reusable specimen, or an independent experiment. Apply the state contract before adding a workflow.
3. **Gate parity claims.** Classify native evidence, require a deterministic fixture for runtime-dependent rendering, and map roles through `--macos-*` then `--fm-*`.
4. **Implement boundedly.** Fixtures are deterministic and local: no network, clock, random data, or simulated production backend. A clickable control proves only the web prototype unless an executable test proves more.
5. **Verify and hand off.** Run the matching checks and record only the evidence actually obtained. Retire a state when its review question is resolved and it has no root consumer.

## Common mistakes

- Porting every historical prototype merely to claim migration completeness.
- Calling a static Storybook rendering a production flow or native behavior.
- Resolving material, geometry, or interactive parity from source or screenshot pixels without a deterministic fixture.
- Using a screenshot hex value directly in component CSS.
- Leaving an isolated workflow after its review question has been decided.
- Treating a successful build as visual-regression, accessibility, or native-parity proof.
