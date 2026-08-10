import type { HomeFavorite, HomeLocation } from "../model/home"

export const homeFavorites: readonly HomeFavorite[] = [
  {
    id: "favorite-research",
    label: "Research Collection",
    glyph: "⌘",
    destinationTabId: "collection",
    pageAnchor: "research-collection",
  },
  {
    id: "favorite-voyager",
    label: "Voyager Design Lab",
    glyph: "✦",
    destinationTabId: "directory",
    pageAnchor: "voyager-design-lab",
  },
  {
    id: "favorite-briefs",
    label: "Product Briefs",
    glyph: "▤",
    destinationTabId: "directory",
    pageAnchor: "product-briefs",
  },
]

export const homeLocations: readonly HomeLocation[] = [
  {
    id: "location-desktop",
    label: "Desktop",
    glyph: "▣",
    destinationTabId: "directory",
    path: "~/Desktop",
  },
  {
    id: "location-documents",
    label: "Documents",
    glyph: "▤",
    destinationTabId: "directory",
    path: "~/Documents",
  },
  {
    id: "location-applications",
    label: "Applications",
    glyph: "⌘",
    destinationTabId: "directory",
    path: "/Applications",
  },
]
