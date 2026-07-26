import type { FC } from "react"
import type { SelectedEntriesCardProps } from "../model/types"

export const SelectedEntriesCard: FC<SelectedEntriesCardProps> = ({ count, primaryName }) => {
  return (
    <div className="quiet-card">
      <span className="eyebrow">Selected Entries</span>
      <strong>{count} selected</strong>
      <p>{primaryName}</p>
    </div>
  )
}

SelectedEntriesCard.displayName = "SelectedEntriesCard"
