import { useMemo } from "react"
import type { FC } from "react"
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

  return (
    <section className="file-browser" aria-label="Entries">
      {viewMode === "grid" ? (
        <EntryGrid
          entries={gridEntries}
          selectedEntryIds={selectedEntryIds}
          onToggleEntry={onToggleEntry}
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
