import type { FC, KeyboardEvent, MouseEvent } from "react"
import type { EntryKind, EntrySelectionIntent } from "../../model/types"
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
  readonly onToggleEntry: (entryId: string, intent: EntrySelectionIntent) => void
  readonly onClearSelection?: () => void
}

export const EntryGrid: FC<EntryGridProps> = ({
  entries,
  selectedEntryIds,
  onToggleEntry,
  onClearSelection,
}) => {
  // 네이티브 mouseDown deselectAll: 그리드 빈 배경 클릭과 Escape로 선택을 해제한다
  function handleBackgroundClick(event: MouseEvent) {
    if (event.target === event.currentTarget) onClearSelection?.()
  }

  function handleKeyDown(event: KeyboardEvent) {
    if (event.key === "Escape") onClearSelection?.()
  }

  return (
    <div className="entry-grid" onClick={handleBackgroundClick} onKeyDown={handleKeyDown}>
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
