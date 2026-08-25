/**
 * Catalog-root registry for the Voyager Storybook surface catalog.
 *
 * Pure data only: no React imports, no CSS, no runtime package code, no
 * filesystem scanning. This module is the single source of truth for which
 * product surfaces are discoverable in Storybook and their lifecycle state.
 *
 * Lifecycle contract (discriminated on `lifecycle`):
 * - `active`: materialized and discovered by `.storybook/main.ts`.
 * - `planned`: approved but not yet materialized; every path field is null.
 * - `retired`: formerly materialized; the type supports it without inventing
 *   a fake retired entry.
 */

/** Surface kind. `foundation` entries are shared design tokens/primitives and
 * have no single root consumer (`rootConsumer: null`). */
export type SurfaceKind = "component" | "foundation" | "embedded-domain"

/**
 * Story discovery spec. Only present on `active` entries; `planned`/`retired`
 * entries keep every field here null.
 */
export interface SurfaceStorySpec {
  /** Storybook directory (relative to `apps/storybook`), e.g. `../src/FileManager`. */
  directory: string
  /** Storybook title prefix applied to every story under `directory`. */
  titlePrefix: string
  /** Story glob, e.g. `**\/*.stories.tsx`. */
  files: string
}

/** Shared fields present on every registry entry regardless of lifecycle. */
interface SurfaceBase {
  /** Stable registry identifier (kebab-case). */
  id: string
  /** Surface kind. */
  kind: SurfaceKind
  /** Owning product surface (accepted/rejects design decisions). */
  owner: string
  /** Point at the owning package's DESIGN.md, relative to `apps/storybook`.
   * Null until the surface is materialized. */
  design: string | null
  /** Owns the deterministic fixtures that render this surface. */
  fixtureOwner: string
  /** Package that owns the materialized stories, relative to `apps/storybook`.
   * Null until the surface is materialized. */
  packageRoot: string | null
  /** Explicit root consumer; null only for `foundation` surfaces. */
  rootConsumer: string | null
}

interface ActiveSurface extends SurfaceBase {
  lifecycle: "active"
  story: SurfaceStorySpec
}

interface PlannedSurface extends SurfaceBase {
  lifecycle: "planned"
  /** Not yet materialized: every story path field is explicitly null. */
  story: null
  /** Retirement condition is not applicable until the surface is active. */
  retirementCondition: null
}

interface RetiredSurface extends SurfaceBase {
  lifecycle: "retired"
  story: null
  /** Condition under which the surface was retired. */
  retirementCondition: string
}

export type Surface = ActiveSurface | PlannedSurface | RetiredSurface

/**
 * All approved catalog surfaces, active and planned, in canonical order.
 * The `active` subset drives `.storybook/main.ts` discovery.
 */
export const surfaceRegistry: readonly Surface[] = [
  {
    id: "design-foundation",
    kind: "foundation",
    lifecycle: "active",
    owner: "Design Foundation",
    design: "packages/design-foundation/DESIGN.md",
    fixtureOwner: "Design Foundation",
    packageRoot: "packages/design-foundation",
    rootConsumer: null,
    story: {
      directory: "../src/DesignFoundation",
      titlePrefix: "Design Foundation",
      files: "**/*.stories.tsx",
    },
  },
  {
    id: "file-manager",
    kind: "component",
    lifecycle: "active",
    owner: "File Manager",
    design: "packages/file-manager-illustration/DESIGN.md",
    fixtureOwner: "File Manager",
    packageRoot: "packages/file-manager-illustration",
    rootConsumer: "FileManagerHost",
    story: {
      directory: "../src/FileManager",
      titlePrefix: "File Manager",
      files: "**/*.stories.tsx",
    },
  },
  {
    id: "settings",
    kind: "component",
    lifecycle: "active",
    owner: "Settings",
    design: "packages/settings-illustration/DESIGN.md",
    fixtureOwner: "Settings",
    packageRoot: "packages/settings-illustration",
    rootConsumer: "SettingsHost",
    story: {
      directory: "../src/Settings",
      titlePrefix: "Settings",
      files: "**/*.stories.tsx",
    },
  },
  {
    id: "onboarding",
    kind: "component",
    lifecycle: "active",
    owner: "Onboarding",
    design: "packages/onboarding-illustration/DESIGN.md",
    fixtureOwner: "Onboarding",
    packageRoot: "packages/onboarding-illustration",
    rootConsumer: "OnboardingHost",
    story: {
      directory: "../src/Onboarding",
      titlePrefix: "Onboarding",
      files: "**/*.stories.tsx",
    },
  },
  {
    id: "feedback",
    kind: "component",
    lifecycle: "planned",
    owner: "Feedback",
    design: null,
    fixtureOwner: "Feedback",
    packageRoot: null,
    rootConsumer: "Voyager",
    story: null,
    retirementCondition: null,
  },
]

/** Active, materialized surfaces that `.storybook/main.ts` discovers. */
export const activeMaterializedSurfaces: readonly ActiveSurface[] = surfaceRegistry.filter(
  (surface): surface is ActiveSurface => surface.lifecycle === "active",
)
