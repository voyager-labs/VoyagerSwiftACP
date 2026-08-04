import { locationIconFixtures } from "../data/location-icon-fixtures"
import type { LocationShortcut, SidebarTabItem } from "../model/types"

export const locationShortcuts: readonly LocationShortcut[] = [
  { id: "home", label: "Home", symbolName: "house", iconSrc: locationIconFixtures.home },
  {
    id: "icloud-drive",
    label: "iCloud Drive",
    symbolName: "icloud",
    iconSrc: locationIconFixtures.iCloudDrive,
  },
  {
    id: "google-drive",
    label: "Google Drive",
    symbolName: "folder",
    iconSrc: locationIconFixtures.googleDrive,
  },
  {
    id: "macintosh-hd",
    label: "Macintosh HD",
    symbolName: "internaldrive",
    iconSrc: locationIconFixtures.macintoshHD,
  },
  {
    id: "external-drive",
    label: "External Drive",
    symbolName: "externaldrive",
    iconSrc: locationIconFixtures.externalDrive,
  },
  { id: "trash", label: "Trash", symbolName: "trash", iconSrc: locationIconFixtures.trash },
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
