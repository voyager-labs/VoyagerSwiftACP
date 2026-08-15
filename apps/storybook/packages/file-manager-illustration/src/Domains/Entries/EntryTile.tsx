import type { FC, MouseEvent } from "react"
import type { EntryKind, EntrySelectionIntent } from "../../model/types"
import { EntryThumbnail } from "./EntryThumbnail"
import type { EntryThumbnailEntry } from "./EntryThumbnail"

export interface EntryTileEntry extends EntryThumbnailEntry {
  readonly name: string
  readonly kind: EntryKind
  readonly meta?: string
  readonly count?: string
}

export interface EntryTileProps {
  entry: EntryTileEntry
  selected: boolean
  onToggle: (entryId: string, intent: EntrySelectionIntent) => void
}

export const EntryTile: FC<EntryTileProps> = ({ entry, selected, onToggle }) => {
  function handleClick(event: MouseEvent) {
    const intent: EntrySelectionIntent = event.shiftKey
      ? "range"
      : event.metaKey
        ? "toggle"
        : "replace"
    onToggle(entry.id, intent)
  }

  return (
    <button
      type="button"
      className={`entry-tile${selected ? " selected" : ""}`}
      aria-selected={selected}
      onClick={handleClick}
    >
      <span className="entry-tile-icon">
        <EntryThumbnail entry={entry} />
      </span>
      <span className="entry-name">{entry.name}</span>
      {entry.meta || entry.count ? (
        <span className="entry-meta">{entry.meta ?? entry.count}</span>
      ) : null}
    </button>
  )
}

EntryTile.displayName = "EntryTile"
