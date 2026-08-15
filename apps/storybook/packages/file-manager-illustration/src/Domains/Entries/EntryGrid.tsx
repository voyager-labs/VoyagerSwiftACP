import type { FC } from "react"
import type { EntryKind } from "../../model/types"
import { EntryTile } from "./EntryTile"
import type { EntryTileEntry } from "./EntryTile"

export interface EntryGridEntry extends EntryTileEntry {
  readonly name: string
  readonly kind: EntryKind
  readonly meta?: string
  readonly count?: string
}

export interface EntryGridProps {
  readonly entries: readonly EntryGridEntry[]
  readonly selectedEntryIds: readonly string[]
  readonly onToggleEntry: (entryId: string, append: boolean) => void
}

export const EntryGrid: FC<EntryGridProps> = ({ entries, selectedEntryIds, onToggleEntry }) => {
  return (
    <div className="entry-grid">
      {entries.map((entry) => (
        <EntryTile
          key={entry.id}
          entry={entry}
          selected={selectedEntryIds.includes(entry.id)}
          onToggle={onToggleEntry}
        />
      ))}
    </div>
  )
}

EntryGrid.displayName = "EntryGrid"
