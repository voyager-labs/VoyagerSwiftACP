# Storybook Workspace Design

Workspace-level workflow owner for the Voyager Storybook surface catalog. This document owns **how the catalog is governed** — registry lifecycle, story ownership, scaffold contract, cross-surface fixture rules, review records, retirement, discovery, and verification routes. It links policy and runtime owners instead of duplicating product truth.

Package-local visual contracts live in each surface package's `DESIGN.md`; process rules live in `.agents/skills/voyager-design-lab/`. This document is the single root that ties them together and owns the workflow they do not.

## 1. Runtime owners (do not duplicate here)

| Concern                                                   | Owned by                                       |
| --------------------------------------------------------- | ---------------------------------------------- |
| Product intent and acceptance criteria                    | Canonical product docs                         |
| Which surfaces are discoverable + lifecycle state         | `surface-registry.ts` (single source of truth) |
| Story discovery globs (`directory`/`titlePrefix`/`files`) | `surface-registry.ts` → `.storybook/main.ts`   |
| Per-surface visual contracts                              | `packages/<surface>/DESIGN.md`                 |
| Skill process rules (add/move/retire, verification)       | `.agents/skills/voyager-design-lab/`           |
| Native parity evidence gate                               | `native-evidence-contract.md`                  |

## 2. Registry lifecycle

`surface-registry.ts` is the single surface inventory. It is pure data: no React, no CSS, no filesystem scanning. Each entry is discriminated on `lifecycle`:

- **`active`** — materialized and discovered. Every story path field is set; the `story` spec drives `.storybook/main.ts`.
- **`planned`** — approved but not yet materialized. Every path field is `null`.
- **`retired`** — formerly materialized. `story` is `null`; a `retirementCondition` records why.

Transitions: add a surface → create its entry (`planned` until stories exist), materialize → flip to `active` with the story spec, remove → set `retired` with a condition. There is exactly one registry; never maintain a second surface inventory.

## 3. Story catalog ownership

Stories live in `apps/storybook/src/{Surface}/` per the active registry entries, not beside package source. The app owns the catalog:

- `src/FileManager/`, `src/Settings/`, `src/DesignFoundation/` mirror the active registry `story.directory` values.
- A component's appearance in Storybook is governed by its **app-owned catalog root**, not by a colocated `*.stories.tsx` next to package source.
- Adding a surface to the catalog is a registry change plus a story-root under `src/`, not a package-local story convention.

## 4. Package scaffold contract

A surface package (`packages/<surface>/`) is the minimal deterministic source unit. Required contract:

- `package.json` — name, `workspace:*` deps, `typecheck` script.
- `tsconfig.json` — strict TS baseline for the package.
- `DESIGN.md` — the surface's visual contract; links the registry root above and the owning product intent.
- Implementation / fixture / style roots under `src/` as the surface needs (components, `data/` fixtures, `styles/`).
- Centralized story path in the registry (`story.directory` under `src/<Surface>/`), not colocated stories.
- Registry entry in `surface-registry.ts`.
- Verification route (package `typecheck`; app `pnpm check`).

Do not add a generator; scaffold each package by hand following an existing package (e.g. `settings-illustration`).

## 5. Cross-surface fixture rules

Fixtures are deterministic and local: no network, clock, random data, or simulated production backend. A fixture belongs to the surface it renders (registry `fixtureOwner`). Shared visual primitives (tokens, SF Symbols, `TabView`) are owned by `design-foundation` and consumed cross-surface through tokens and the `--macos-*` chain — never duplicated per surface.

## 6. Review records and retirement

Every material state carries a review record (see `review-and-verification.md`): Decision, Authority, Checked, Unknown/deviation, Follow-up. A surface or state is retired when its review question is resolved and it has no root consumer; record the retirement in the registry (`lifecycle: "retired"` + `retirementCondition`) and in the review record.

## 7. Discovery and verification routes

- Discovery is registry-driven: `surface-registry.ts` → `.storybook/main.ts` → Storybook. To add/move/retire a surface, edit the registry and the story root, never a parallel discovery mechanism.
- Verification is change-scoped: a Storybook-only package/catalog change is proven by Storybook evidence (`pnpm check`, `build-storybook`, `verify:contract`); native evidence is required only for the runtime claims named by `native-evidence-contract.md`. This workspace never claims native parity from a static render.
