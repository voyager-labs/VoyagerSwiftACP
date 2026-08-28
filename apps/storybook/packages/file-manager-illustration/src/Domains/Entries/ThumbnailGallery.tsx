import type { FC } from "react"
import type { EntryKind } from "../../model/types"
import { EntryThumbnail } from "./EntryThumbnail"
import type { EntryThumbnailComparisonEntry } from "./EntryThumbnailComparison"

const KIND_ORDER: readonly EntryKind[] = [
  "pdf",
  "image",
  "folder",
  "sheet",
  "doc",
  "video",
  "archive",
]

const KIND_LABELS: Record<EntryKind, string> = {
  pdf: "PDF",
  image: "Image",
  folder: "Folder",
  sheet: "Spreadsheet",
  doc: "Document",
  video: "Video",
  archive: "Archive",
}

export interface ThumbnailGalleryProps {
  entries: readonly EntryThumbnailComparisonEntry[]
}

export const ThumbnailGallery: FC<ThumbnailGalleryProps> = ({ entries }) => {
  // kind별로 그룹핑하여 각 섹션 렌더링
  const groups = KIND_ORDER.map((kind) => ({
    kind,
    label: KIND_LABELS[kind],
    items: entries.filter((e) => e.kind === kind),
  })).filter((g) => g.items.length > 0)

  return (
    <div className="thumbnail-gallery" aria-label="Thumbnail gallery by kind">
      {groups.map((group) => (
        <section key={group.kind} className="gallery-section">
          <h3 className="gallery-section-title">{group.label}</h3>
          <div className="gallery-cards">
            {group.items.map((entry) => (
              <div key={entry.id} className="gallery-card">
                <span className="gallery-card-thumb">
                  <EntryThumbnail entry={entry} />
                </span>
                <span className="gallery-card-label">{entry.label}</span>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  )
}

ThumbnailGallery.displayName = "ThumbnailGallery"
