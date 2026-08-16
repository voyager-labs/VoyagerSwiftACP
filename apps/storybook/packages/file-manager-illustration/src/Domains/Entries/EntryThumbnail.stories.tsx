import type { Meta, StoryObj } from "@storybook/react-vite"
import { thumbnailComparisonEntries } from "../../data/mock-data"
import type { EntryKind } from "../../model/types"
import { EntryThumbnail } from "./EntryThumbnail"
import type { EntryThumbnailComparisonEntry } from "./EntryThumbnailComparison"
import { EntryThumbnailComparison } from "./EntryThumbnailComparison"
import { ThumbnailGallery } from "./ThumbnailGallery"

const meta = {
  component: EntryThumbnail,
  tags: ["autodocs"],
  args: {
    entry: thumbnailComparisonEntries[0],
    size: "regular",
  },
} satisfies Meta<typeof EntryThumbnail>

export default meta

// kind별 모든 배리에이션을 갤러리 그리드로 렌더링
function renderKindVariations(kind: EntryKind, size?: "regular" | "small") {
  const entries = thumbnailComparisonEntries.filter((e) => e.kind === kind)
  return (
    <div className="thumbnail-gallery">
      <section className="gallery-section">
        <div className="gallery-cards">
          {entries.map((entry: EntryThumbnailComparisonEntry) => (
            <div key={entry.id} className="gallery-card">
              <span className="gallery-card-thumb">
                <EntryThumbnail entry={entry} size={size} />
              </span>
              <span className="gallery-card-label">{entry.label}</span>
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}

type VariationStory = StoryObj<typeof meta>

export const Pdf: VariationStory = {
  render: () => renderKindVariations("pdf"),
}

export const Image: VariationStory = {
  render: () => renderKindVariations("image"),
}

export const Folder: VariationStory = {
  render: () => renderKindVariations("folder"),
}

export const Sheet: VariationStory = {
  render: () => renderKindVariations("sheet"),
}

export const Doc: VariationStory = {
  render: () => renderKindVariations("doc"),
}

export const Video: VariationStory = {
  render: () => renderKindVariations("video"),
}

export const Archive: VariationStory = {
  render: () => renderKindVariations("archive"),
}

export const PdfSmall: VariationStory = {
  render: () => renderKindVariations("pdf", "small"),
}

export const ImageSmall: VariationStory = {
  render: () => renderKindVariations("image", "small"),
}

export const FolderSmall: VariationStory = {
  render: () => renderKindVariations("folder", "small"),
}

export const SheetSmall: VariationStory = {
  render: () => renderKindVariations("sheet", "small"),
}

export const DocSmall: VariationStory = {
  render: () => renderKindVariations("doc", "small"),
}

export const VideoSmall: VariationStory = {
  render: () => renderKindVariations("video", "small"),
}

export const ArchiveSmall: VariationStory = {
  render: () => renderKindVariations("archive", "small"),
}

export const AllKindsAndSizes: StoryObj<{
  component: typeof EntryThumbnailComparison
  args: { entries: readonly EntryThumbnailComparisonEntry[] }
}> = {
  render: () => <EntryThumbnailComparison entries={thumbnailComparisonEntries} />,
}

export const AllVariations: StoryObj<{
  component: typeof ThumbnailGallery
  args: { entries: readonly EntryThumbnailComparisonEntry[] }
}> = {
  render: () => <ThumbnailGallery entries={thumbnailComparisonEntries} />,
}
