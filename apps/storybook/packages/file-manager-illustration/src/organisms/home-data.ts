import type { HomeFavorite, HomeLocation, HomeRecentChat } from "./Home"

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

export const homeRecentChats: readonly HomeRecentChat[] = [
  {
    id: "chat-research-summary",
    sessionId: "session-research-summary",
    title: "Summarize research notes",
    detail: "Research Collection",
    updatedLabel: "12m ago",
    destinationTabId: "ai-chat",
  },
  {
    id: "chat-project-plan",
    sessionId: "session-project-plan",
    title: "Outline the project plan",
    detail: "Voyager Design Lab",
    updatedLabel: "Yesterday",
    destinationTabId: "ai-chat",
  },
  {
    id: "chat-release-notes",
    sessionId: "session-release-notes",
    title: "Draft release notes",
    detail: "Product Briefs",
    updatedLabel: "Mon",
    destinationTabId: "ai-chat",
  },
]
