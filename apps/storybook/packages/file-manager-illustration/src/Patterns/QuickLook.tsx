import type { FC } from "react"
import { Button } from "../UI/Controls/Button"
import { EntryThumbnail } from "../Entries/EntryThumbnail"
import type { EntryThumbnailEntry } from "../Entries/EntryThumbnail"
import type { EntryKind } from "../model/types"

export interface QuickLookEntry extends EntryThumbnailEntry {
  readonly name: string
  readonly kind: EntryKind
  readonly meta?: string
  readonly count?: string
}

export interface QuickLookProps {
  readonly entry: QuickLookEntry
}

export const QuickLook: FC<QuickLookProps> = ({ entry }) => {
  return (
    <section className="vc-stage">
      <div className="fm-quick-look vc-window">
        <header>
          <strong>{entry.name}</strong>
          <Button variant="primary" pill>
            Open
          </Button>
        </header>
        <div className="fm-quick-look-preview">
          <EntryThumbnail entry={entry} />
        </div>
        <footer>
          <span>{entry.kind.toUpperCase()}</span>
          <span>{entry.meta ?? entry.count ?? "No additional metadata"}</span>
        </footer>
      </div>
    </section>
  )
}

QuickLook.displayName = "QuickLook"
