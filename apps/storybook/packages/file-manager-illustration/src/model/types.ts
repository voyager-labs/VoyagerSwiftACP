export type EntryKind = "pdf" | "image" | "folder" | "sheet" | "doc" | "video" | "archive"

/** Public file projection — the only file shape consumers pass. */
export type FileEntry = {
  readonly id: string
  readonly displayName: string
  readonly kind: EntryKind
  readonly extension: string | null
  readonly secondaryLabel: string | null
  readonly thumbnailSrc?: string
}

export type SidebarIconKind = "home" | "folder" | "folder-blue" | "collection" | "chat"

/** Internal breadcrumb segment with SF Symbol name for icon rendering. */
export type BreadcrumbSegment = {
  readonly label: string
  readonly symbolName: string
}

export type SidebarTabItem = {
  readonly id: string
  readonly label: string
  readonly icon: SidebarIconKind
  readonly active?: boolean
  readonly isPinned?: boolean
  readonly secondary?: string
  readonly pageAnchor?: string
  readonly breadcrumb?: readonly BreadcrumbSegment[]
}

export type SidebarTabAction = (item: SidebarTabItem) => void

export type ContentTab = {
  readonly id: string
  readonly label: string
}

export type ContentContext = {
  readonly tabs: readonly ContentTab[]
  readonly activeTabId: string | null
}

export type SelectedEntriesCardProps = {
  readonly count: number
  readonly primaryName: string
}

export type InspectorChatInputProps = {
  readonly requestText: string
  readonly onRequestTextChange: (value: string) => void
}

export type SearchFieldProps = {
  readonly value?: string
  readonly placeholder?: string
  readonly resultCount?: number
}

export type LocationShortcut = {
  readonly id: string
  readonly label: string
  readonly symbolName: string
  readonly iconSrc?: string
}

export type LocationShortcutsProps = {
  readonly shortcuts: readonly LocationShortcut[]
  readonly onSelect?: (shortcut: LocationShortcut) => void
}

export type SidebarSectionProps = {
  readonly items: readonly SidebarTabItem[]
  readonly title?: string
  readonly compact?: boolean
}

export type SidebarIconProps = {
  readonly icon: SidebarIconKind
  readonly isActive?: boolean
}

export type SidebarNavItemProps = {
  readonly item: SidebarTabItem
  readonly actionRevealed?: boolean
  readonly onSelect?: SidebarTabAction
  readonly onUnpin?: SidebarTabAction
  readonly onClose?: SidebarTabAction
}

export type TrafficLightsProps = Record<string, never>

export type ContextMenuAction = {
  readonly id: string
  readonly label: string
  readonly shortcut?: string
  readonly destructive?: boolean
  readonly disabled?: boolean
}

export type Entry = {
  readonly id: string
  readonly name: string
  readonly kind: EntryKind
  readonly meta?: string
  readonly count?: string
  readonly thumbnailSrc?: string
}

export type FileManagerIllustrationProps = {
  readonly files: readonly FileEntry[]
  readonly contentContext: ContentContext
}
