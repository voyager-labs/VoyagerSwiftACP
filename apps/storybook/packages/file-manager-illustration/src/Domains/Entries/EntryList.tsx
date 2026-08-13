import type { FC } from "react"
import type { EntryKind, EntrySelectionIntent } from "../../model/types"
import { EntryListRow } from "./EntryListRow"
import type { EntryListRowEntry } from "./EntryListRow"

export interface EntryListEntry extends EntryListRowEntry {
  readonly name: string
  readonly kind: EntryKind
  readonly meta?: string
  readonly count?: string
}

export interface EntryListProps {
  readonly entries: readonly EntryListEntry[]
  readonly selectedEntryIds: readonly string[]
  readonly onToggleEntry: (entryId: string, intent: EntrySelectionIntent) => void
}

export const EntryList: FC<EntryListProps> = ({ entries, selectedEntryIds, onToggleEntry }) => {
  return (
    <table className="entry-list" aria-label="Files">
      <thead>
        <tr className="entry-list-header">
          <th scope="col">Name</th>
          <th scope="col">Date Modified</th>
          <th scope="col">Size</th>
          <th scope="col">Kind</th>
        </tr>
      </thead>
      <tbody>
        {entries.map((entry) => (
          <EntryListRow
            key={entry.id}
            entry={entry}
            selected={selectedEntryIds.includes(entry.id)}
            onToggle={onToggleEntry}
          />
        ))}
      </tbody>
    </table>
  )
}

EntryList.displayName = "EntryList"
