import type { FC, MouseEvent } from "react"
import type { EntryKind } from "../../model/types"
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
  onToggle: (entryId: string, append: boolean) => void
}

export const EntryTile: FC<EntryTileProps> = ({ entry, selected, onToggle }) => {
  function handleClick(event: MouseEvent) {
    onToggle(entry.id, event.metaKey || event.shiftKey)
  }

  return (
    <button
      type="button"
      className={`entry-tile${selected ? " selected" : ""}`}
      aria-selected={selected}
      onClick={handleClick}
    >
      <EntryThumbnail entry={entry} />
      <span className="entry-name">{entry.name}</span>
      {entry.meta || entry.count ? (
        <span className="entry-meta">{entry.meta ?? entry.count}</span>
      ) : null}
    </button>
  )
}

EntryTile.displayName = "EntryTile"
