import type { FC } from "react"
import { EntryThumbnail } from "./EntryThumbnail"
import type { EntryThumbnailEntry } from "./EntryThumbnail"

export interface EntryThumbnailComparisonProps {
  entries: readonly EntryThumbnailEntry[]
}

export const EntryThumbnailComparison: FC<EntryThumbnailComparisonProps> = ({ entries }) => (
  <div className="entry-thumbnail-comparison" aria-label="Entry thumbnail comparison">
    <div className="comparison-row comparison-kinds">
      <span />
      {entries.map((entry) => (
        <span key={entry.id} className="comparison-kind">
          {entry.kind}
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
