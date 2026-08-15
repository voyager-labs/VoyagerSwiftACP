import type { FC, KeyboardEvent, MouseEvent } from "react"
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
  readonly onClearSelection?: () => void
}

export const EntryList: FC<EntryListProps> = ({
  entries,
  selectedEntryIds,
  onToggleEntry,
  onClearSelection,
}) => {
  function handleBodyClick(event: MouseEvent<HTMLTableSectionElement>) {
    if (event.target === event.currentTarget) onClearSelection?.()
  }

  function handleBodyKeyDown(event: KeyboardEvent<HTMLTableSectionElement>) {
    if (event.key === "Escape") onClearSelection?.()
  }

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
      <tbody onClick={handleBodyClick} onKeyDown={handleBodyKeyDown}>
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
