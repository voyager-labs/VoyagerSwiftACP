import type {
  BreadcrumbSegment,
  ContentTab,
  Entry,
  FileEntry,
  FileManagerIllustrationProps,
  SidebarTabItem,
} from "../model/types"
import { contentTabs } from "./navigation-data"

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
  const knownTab = contentTabs.find((ct) => ct.id === tab.id)
  return { id: tab.id, label: tab.label, icon, isPinned, breadcrumb: knownTab?.breadcrumb }
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

/** Derive icon-bearing breadcrumb segments from active tab and selection state. */
export function deriveBreadcrumbSegments(
  activeTab: SidebarTabItem | null,
  selectedEntries: readonly Entry[],
): readonly BreadcrumbSegment[] {
  const base =
    activeTab?.breadcrumb ?? (activeTab ? [{ label: activeTab.label, symbolName: "folder" }] : [])

  if (selectedEntries.length === 1) {
    const entry = selectedEntries[0]
    const leafSymbol = entry.kind === "folder" ? "folder" : "doc"
    return [...base, { label: entry.name, symbolName: leafSymbol }]
  }

  return base
}

/** Derive selection status label. */
export function deriveSelectionLabel(selectedCount: number, totalCount: number): string {
  if (selectedCount === 0) return `${totalCount} items`
  return `${selectedCount} of ${totalCount} selected`
}
