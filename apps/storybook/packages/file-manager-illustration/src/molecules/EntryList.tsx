import type { FC } from "react"
import { EntryListRow } from "../atoms/EntryListRow"
import type { EntryListRowEntry } from "../atoms/EntryListRow"
import type { EntryKind } from "../types"

export interface EntryListEntry extends EntryListRowEntry {
  readonly name: string
  readonly kind: EntryKind
  readonly meta?: string
  readonly count?: string
}

export interface EntryListProps {
  readonly entries: readonly EntryListEntry[]
  readonly selectedEntryIds: readonly string[]
  readonly onToggleEntry: (entryId: string, append: boolean) => void
}

export const EntryList: FC<EntryListProps> = ({ entries, selectedEntryIds, onToggleEntry }) => {
  return (
    <div className="entry-list">
      <div className="entry-list-header" aria-hidden="true">
        <span>Name</span>
        <span>Kind</span>
        <span>Info</span>
        <span>Location</span>
      </div>
      {entries.map((entry) => (
        <EntryListRow
          key={entry.id}
          entry={entry}
          selected={selectedEntryIds.includes(entry.id)}
          onToggle={onToggleEntry}
        />
      ))}
    </div>
  )
}

EntryList.displayName = "EntryList"
