import type { FC, KeyboardEvent, MouseEvent } from "react"
import type { EntryKind, EntrySelectionIntent } from "../../model/types"
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
  onToggle: (entryId: string, intent: EntrySelectionIntent) => void
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
  const extensionIndex = entry.name.lastIndexOf(".")
  const hasExtension = extensionIndex > 0 && extensionIndex < entry.name.length - 1
  const leadingName = hasExtension ? entry.name.slice(0, extensionIndex) : entry.name
  const trailingName = hasExtension ? entry.name.slice(extensionIndex) : ""

  function handleClick(event: MouseEvent) {
    const intent: EntrySelectionIntent = event.shiftKey
      ? "range"
      : event.metaKey
        ? "toggle"
        : "replace"
    onToggle(entry.id, intent)
  }

  function handleKeyDown(event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return
    event.preventDefault()
    onToggle(entry.id, event.shiftKey ? "range" : event.metaKey ? "toggle" : "replace")
  }

  return (
    <tr
      className={`entry-list-row${selected ? " selected" : ""}`}
      aria-selected={selected}
      aria-label={entry.name}
      tabIndex={0}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
    >
      <td className="entry-list-name">
        <EntryThumbnail entry={entry} size="small" />
        <span className="entry-list-name-text">
          <span className="entry-list-name-leading">{leadingName}</span>
          <span className="entry-list-name-trailing">{trailingName}</span>
        </span>
      </td>
      <td className="entry-date-modified">{entry.dateModified ?? "—"}</td>
      <td className="entry-size">{entry.size ?? "—"}</td>
      <td className="entry-kind">{kindLabels[entry.kind]}</td>
    </tr>
  )
}

EntryListRow.displayName = "EntryListRow"
