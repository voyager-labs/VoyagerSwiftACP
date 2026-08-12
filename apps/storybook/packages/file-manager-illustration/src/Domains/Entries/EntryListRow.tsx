import type { FC, MouseEvent } from "react"
import type { EntryKind } from "../../model/types"
import { EntryThumbnail } from "./EntryThumbnail"
import type { EntryThumbnailEntry } from "./EntryThumbnail"

export interface EntryListRowEntry extends EntryThumbnailEntry {
  readonly name: string
  readonly kind: EntryKind
  readonly dateModified?: string
  readonly size?: string
  readonly meta?: string
  readonly count?: string
}

export interface EntryListRowProps {
  entry: EntryListRowEntry
  selected: boolean
  onToggle: (entryId: string, append: boolean) => void
}

const kindLabels: Record<EntryKind, string> = {
  archive: "Archive",
  doc: "Document",
  folder: "Folder",
  image: "Image",
  pdf: "PDF",
  sheet: "Spreadsheet",
  video: "Video",
}

export const EntryListRow: FC<EntryListRowProps> = ({ entry, selected, onToggle }) => {
  function handleClick(event: MouseEvent) {
    onToggle(entry.id, event.metaKey || event.shiftKey)
  }

  return (
    <button
      type="button"
      className={`entry-list-row${selected ? " selected" : ""}`}
      aria-selected={selected}
      onClick={handleClick}
    >
      <EntryThumbnail entry={entry} size="small" />
      <span className="entry-list-name">{entry.name}</span>
      <span className="entry-date-modified">{entry.dateModified ?? "—"}</span>
      <span className="entry-size">{entry.size ?? "—"}</span>
      <span className="entry-kind">{kindLabels[entry.kind]}</span>
    </button>
  )
}

EntryListRow.displayName = "EntryListRow"
