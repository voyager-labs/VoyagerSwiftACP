import type { FC } from "react"
import type { Entry } from "./types"

export interface PropertiesPaneProps {
  readonly selectedEntries: readonly Entry[]
  readonly primaryEntry: Entry | null
}

export const PropertiesPane: FC<PropertiesPaneProps> = ({ selectedEntries, primaryEntry }) => {
  return (
    <section className="vc-properties-pane">
      {primaryEntry != null ? (
        <>
          <span className="vc-eyebrow">Entry</span>
          <h2>{primaryEntry.name}</h2>
          <dl>
            <div>
              <dt>Kind</dt>
              <dd>{primaryEntry.kind}</dd>
            </div>
            <div>
              <dt>Selection</dt>
              <dd>{selectedEntries.length} entries</dd>
            </div>
            <div>
              <dt>Location</dt>
              <dd>~/Desktop/Voyager</dd>
            </div>
          </dl>
        </>
      ) : (
        <p className="vc-empty-text">No file selected</p>
      )}
    </section>
  )
}

PropertiesPane.displayName = "PropertiesPane"
