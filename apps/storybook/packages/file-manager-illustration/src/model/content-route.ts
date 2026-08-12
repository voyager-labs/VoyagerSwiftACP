import type { SidebarTabItem } from "./types"

/**
 * Exhaustive discriminated union for the content area route.
 * Mirrors the native macOS ContentTabPageAnchor enum.
 */
export type ContentRoute =
  | { readonly kind: "home" }
  | { readonly kind: "browser"; readonly pageAnchor?: string }

/** Derive ContentRoute from the active SidebarTabItem (not just id). */
export function deriveContentRoute(activeTab: SidebarTabItem | null): ContentRoute {
  if (activeTab === null) return { kind: "home" }
  if (activeTab.id === "home" || activeTab.icon === "home") {
    return { kind: "home" }
  }
  return { kind: "browser", pageAnchor: activeTab.pageAnchor }
}
