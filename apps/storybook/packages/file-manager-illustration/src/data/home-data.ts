import type { HomeChat, HomeFavorite, HomeLocation } from "../model/home"

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

// native FileManagerHomePageView recentChatsSection — deterministic, clock 미의존 (relativeTime 고정)
export const homeRecentChats: readonly HomeChat[] = [
  {
    id: "chat-1",
    title: "Review collection PDFs",
    detail: "12 messages",
    relativeTime: "just now",
  },
  {
    id: "chat-2",
    title: "Summarize research notes",
    detail: "4 messages",
    relativeTime: "2h ago",
  },
  {
    id: "chat-3",
    title: "Group duplicates by theme",
    detail: "7 messages",
    relativeTime: "1d ago",
  },
]
