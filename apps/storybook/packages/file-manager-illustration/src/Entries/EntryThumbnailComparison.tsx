import type { FC } from "react"
import type { EntryThumbnailEntry } from "./EntryThumbnail"
import { EntryThumbnail } from "./EntryThumbnail"

export interface EntryThumbnailComparisonEntry extends EntryThumbnailEntry {
  readonly label: string
}

export interface EntryThumbnailComparisonProps {
  entries: readonly EntryThumbnailComparisonEntry[]
}

export const EntryThumbnailComparison: FC<EntryThumbnailComparisonProps> = ({ entries }) => (
  <div className="entry-thumbnail-comparison" aria-label="Entry thumbnail comparison">
    <div className="comparison-row comparison-kinds">
      <span />
      {entries.map((entry) => (
        <span key={entry.id} className="comparison-kind">
          {entry.label}
        </span>
      ))}
    </div>

    <div className="comparison-row">
      <span className="comparison-row-label">Regular</span>
      {entries.map((entry) => (
        <span key={entry.id} className="comparison-thumbnail">
          <EntryThumbnail entry={entry} />
        </span>
      ))}
    </div>

    <div className="comparison-row">
      <span className="comparison-row-label">Small</span>
      {entries.map((entry) => (
        <span key={entry.id} className="comparison-thumbnail">
          <EntryThumbnail entry={entry} size="small" />
        </span>
      ))}
    </div>
  </div>
)

EntryThumbnailComparison.displayName = "EntryThumbnailComparison"
