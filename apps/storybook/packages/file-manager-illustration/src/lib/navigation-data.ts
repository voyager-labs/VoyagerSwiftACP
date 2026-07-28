import type { LocationShortcut, SidebarTabItem } from "../model/types"

export const locationShortcuts: readonly LocationShortcut[] = [
  { id: "local-entries", label: "Local Entries", glyph: "▣" },
  { id: "cloud-entries", label: "Cloud Entries", glyph: "☁" },
  { id: "trash", label: "Trash", glyph: "⌫" },
]

export const pinnedTabs: readonly SidebarTabItem[] = [
  { id: "recents", label: "Recents", icon: "folder", isPinned: true },
  { id: "downloads", label: "Downloads", icon: "folder", isPinned: true },
  { id: "desktop", label: "Desktop", icon: "folder", isPinned: true },
  { id: "documents", label: "Documents", icon: "folder", isPinned: true },
  { id: "projects", label: "Projects", icon: "folder", isPinned: true },
]

export const contentTabs: readonly SidebarTabItem[] = [
  { id: "home", label: "Home Page", icon: "home" },
  { id: "directory", label: "Directory", icon: "folder-blue", active: true },
  { id: "collection", label: "Research Collection", icon: "collection" },
]
