# Translation Workflow

Read this reference when moving structure, state, geometry, or style between native macOS source and Storybook in either direction.

## Directions

| Direction                            | Trigger                                                                            | Authority flow                                                                                                             |
| ------------------------------------ | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| native → Storybook (reflect)         | Native implementation exists; Storybook must reproduce its structure/states        | Native source is authority; Storybook translates it into an inspectable review state                                       |
| Storybook → native (prototype-first) | No native implementation yet; Storybook explores a surface later adopted by native | Storybook is `experiment` until native implementation lands; then native becomes authority and Storybook aligns or retires |

## native → Storybook (reflect)

1. Read the owning native SwiftUI/AppKit view as authority before writing TSX. Record the source path with the translated component.
2. Extract in this order: composition tree, presentation/state branches, geometry (heights/widths/padding/spacing), then semantic roles (color/material/symbol). Do not extract from screenshots.
3. Map every dynamic value through the token chain (`native semantic role → --macos-* → --fm-* → component CSS`). See `native-evidence-contract.md`.
4. Replace runtime-dependent data (network responses, clocks, streaming, random) with deterministic named fixtures. A fixture is local, offline, and stable.
5. Port native callbacks/actions as Storybook props or reducer actions; do not invent product behavior the native source does not declare.
6. Mark any native value you cannot confirm from source (material compositing, intrinsic dimensions, dynamic appearance) as an explicit unknown in the story or review record. Do not guess.

## Storybook → native (prototype-first)

1. Before prototyping, write the isolated-state review contract (Question, Authority=`experiment`, Fixture, Owner, Retirement) from `authority-and-state-contract.md`. A prototype without this contract is catalog debt.
2. Prototype in TSX/CSS under the token chain. Keep the surface inside the root composition when it is intended to replace or precede a native surface.
3. When native implementation begins, native source becomes authority. Update the Storybook surface to reflect the shipped native structure, or retire it per the review contract.
4. Never let the prototype override native source after native implementation exists. A stale prototype that contradicts native is catalog debt.

## Story grouping (single axis)

The illustration is one window; organize story source under `src/<Surface>/` on a single axis with four categories, mirroring the File Manager topology:

- **`Foundations/`** — product-agnostic visual primitives and controls (shared via `design-foundation` when cross-surface).
- **`Domains/`** — feature domains that own product language, fixtures, and stateful review flows (e.g. `Domains/Entries`, `Domains/Chat`, `Domains/Composer`).
- **`Pages/`** — window/page compositions and panes that place domains within the shell and own geometry and scroll boundaries.
- **`Stories/`** — root composition(s) that integrate the surface (e.g. `FileManagerIllustration`).

There is no `Layouts` or `Patterns` category: chrome/interaction structures that combine primitives without owning a product workflow, and window-shell geometry, are placed under `Pages/`; reusable domain compositions stay inside their owning `Domains/` folder. A feature domain with its own native package (e.g. Chat ↔ `VoyagerFeaturesAiChat`) gets its own folder under `Domains/`.

Rules:

- The root composition (`Stories/`) is the only canonical integration point. Category folders hold specimens of one surface, not parallel roots.
- Apply `authority-and-state-contract.md` to each story: root consumer, reusable specimen, or experiment.

## What translation does not change

- Product intent and acceptance criteria stay in canonical product docs.
- A successful Storybook build does not prove native parity, accessibility, or visual regression (see `review-and-verification.md`).
- Dynamic colors, materials, and interaction visuals still require deterministic native capture before a parity claim (see `native-evidence-contract.md`).
