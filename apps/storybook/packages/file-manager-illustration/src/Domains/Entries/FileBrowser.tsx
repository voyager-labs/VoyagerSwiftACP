import { useMemo } from "react"
import type { FC, KeyboardEvent, MouseEvent } from "react"
import type { EntryViewMode } from "../../Patterns/Content/FileToolbar"
import type { Entry, EntrySelectionIntent } from "../../model/types"
import { EntryGrid } from "./EntryGrid"
import type { EntryGridEntry } from "./EntryGrid"
import { EntryList } from "./EntryList"
import type { EntryListEntry } from "./EntryList"

/* Structural map: Entry has the same shape as EntryGridEntry/EntryListEntry. */
function toGridEntry(e: Entry): EntryGridEntry {
  return {
    id: e.id,
    name: e.name,
    kind: e.kind,
    meta: e.meta,
    count: e.count,
    thumbnailSrc: e.thumbnailSrc,
  }
}
function toListEntry(e: Entry): EntryListEntry {
  return {
    id: e.id,
    name: e.name,
    kind: e.kind,
    dateModified: e.dateModified,
    size: e.size,
    meta: e.meta,
    count: e.count,
    thumbnailSrc: e.thumbnailSrc,
  }
}

export interface FileBrowserProps {
  readonly entries: readonly Entry[]
  readonly selectedEntryIds: readonly string[]
  readonly viewMode: EntryViewMode
  readonly onToggleEntry: (entryId: string, intent: EntrySelectionIntent) => void
  readonly onClearSelection?: () => void
}

export const FileBrowser: FC<FileBrowserProps> = ({
  entries,
  selectedEntryIds,
  viewMode,
  onToggleEntry,
  onClearSelection,
}) => {
  const gridEntries = useMemo(() => entries.map(toGridEntry), [entries])
  const listEntries = useMemo(() => entries.map(toListEntry), [entries])

  // 네이티브 mouseDown deselectAll: 브라우저 표면의 빈 영역(엔트리가 아닌 곳) 클릭과 Escape로 선택을 해제한다
  function handleBackgroundClick(event: MouseEvent) {
    if (onClearSelection == null) return
    const target = event.target as HTMLElement
    if (target.closest(".entry-tile, .entry-list-row") != null) return
    onClearSelection()
  }

  function handleKeyDown(event: KeyboardEvent) {
    if (event.key === "Escape") onClearSelection?.()
  }

  return (
    <section
      className="file-browser"
      aria-label="Entries"
      onClick={handleBackgroundClick}
      onKeyDown={handleKeyDown}
    >
      {viewMode === "grid" ? (
        <EntryGrid
          entries={gridEntries}
          selectedEntryIds={selectedEntryIds}
          onToggleEntry={onToggleEntry}
          onClearSelection={onClearSelection}
        />
      ) : (
        <EntryList
          entries={listEntries}
          selectedEntryIds={selectedEntryIds}
          onToggleEntry={onToggleEntry}
          onClearSelection={onClearSelection}
        />
      )}
    </section>
  )
}

FileBrowser.displayName = "FileBrowser"
