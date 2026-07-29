import type { ContentRoute } from "../model/content-route"
import type {
  ContentTab,
  Entry,
  FileEntry,
  FileManagerIllustrationProps,
  SidebarTabItem,
} from "../model/types"

/** Convert public FileEntry to internal Entry. */
export function toEntry(f: FileEntry): Entry {
  return {
    id: f.id,
    name: f.displayName,
    kind: f.kind,
    meta: f.secondaryLabel ?? f.extension ?? undefined,
    thumbnailSrc: f.thumbnailSrc,
  }
}

/** Convert public ContentTab to SidebarTabItem with sensible defaults. */
export function toSidebarTabItem(tab: ContentTab): SidebarTabItem {
  const icon = tab.id === "home" ? "home" : "folder-blue"
  const isPinned = ["recents", "downloads", "desktop", "documents", "projects"].includes(tab.id)
  return { id: tab.id, label: tab.label, icon, isPinned }
}

/** Convert public props to reducer initial params. */
export function propsToInitialParams(props: FileManagerIllustrationProps): {
  files: readonly Entry[]
  tabs: readonly SidebarTabItem[]
  activeTabId: string | null
} {
  return {
    files: props.files.map(toEntry),
    tabs: props.contentContext.tabs.map(toSidebarTabItem),
    activeTabId: props.contentContext.activeTabId,
  }
}

/** Derive breadcrumb text from route. */
export function deriveBreadcrumb(route: ContentRoute, activeTab: SidebarTabItem | null): string {
  if (route.kind === "browser") {
    const segments = route.pageAnchor?.split("/").filter((segment) => segment.length > 0)
    return segments && segments.length > 0
      ? segments.join(" / ")
      : (activeTab?.label ?? "Directory")
  }
  return ""
}

/** Derive selection status label. */
export function deriveSelectionLabel(selectedCount: number, totalCount: number): string {
  if (selectedCount === 0) return `${totalCount} items`
  return `${selectedCount} of ${totalCount} selected`
}
