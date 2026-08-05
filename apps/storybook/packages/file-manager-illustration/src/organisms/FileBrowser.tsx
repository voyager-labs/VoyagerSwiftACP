import { useMemo } from "react"
import type { FC } from "react"
import type { Entry } from "../model/types"
import { EntryGrid } from "../molecules/EntryGrid"
import type { EntryGridEntry } from "../molecules/EntryGrid"
import { EntryList } from "../molecules/EntryList"
import type { EntryListEntry } from "../molecules/EntryList"
import type { EntryViewMode } from "../molecules/FileToolbar"

/* Structural map: Entry has the same shape as EntryGridEntry/EntryListEntry. */
function toGridEntry(e: Entry): EntryGridEntry {
  return { id: e.id, name: e.name, kind: e.kind, meta: e.meta, count: e.count }
}
function toListEntry(e: Entry): EntryListEntry {
  return { id: e.id, name: e.name, kind: e.kind, meta: e.meta, count: e.count }
}

export interface FileBrowserProps {
  readonly entries: readonly Entry[]
  readonly selectedEntryIds: readonly string[]
  readonly viewMode: EntryViewMode
  readonly onToggleEntry: (entryId: string, append: boolean) => void
}

export const FileBrowser: FC<FileBrowserProps> = ({
  entries,
  selectedEntryIds,
  viewMode,
  onToggleEntry,
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
        />
      )}
    </section>
  )
}

FileBrowser.displayName = "FileBrowser"
