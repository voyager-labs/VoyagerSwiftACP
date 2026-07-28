import type { Meta, StoryObj } from "@storybook/react-vite"
import { EntryThumbnail } from "./EntryThumbnail"
import type { EntryThumbnailEntry } from "./EntryThumbnail"
import { EntryThumbnailComparison } from "./EntryThumbnailComparison"

const entryKindEntries: readonly EntryThumbnailEntry[] = [
  { id: "e01", kind: "pdf" },
  { id: "e23", kind: "image" },
  { id: "e20", kind: "folder" },
  { id: "e53", kind: "sheet" },
  { id: "e56", kind: "doc" },
  { id: "e70", kind: "video" },
  { id: "e40", kind: "archive" },
]

const meta = {
  component: EntryThumbnail,
  tags: ["autodocs"],
  args: {
    entry: entryKindEntries[0],
    size: "regular",
  },
} satisfies Meta<typeof EntryThumbnail>

export default meta
type Story = StoryObj<typeof meta>

export const Pdf: Story = {}

export const Image: Story = {
  args: {
    entry: entryKindEntries[1],
  },
}

export const Folder: Story = {
  args: {
    entry: entryKindEntries[2],
  },
}

export const Sheet: Story = {
  args: {
    entry: entryKindEntries[3],
  },
}

export const Doc: Story = {
  args: {
    entry: entryKindEntries[4],
  },
}

export const Video: Story = {
  args: {
    entry: entryKindEntries[5],
  },
}

export const Archive: Story = {
  args: {
    entry: entryKindEntries[6],
  },
}

export const PdfSmall: Story = {
  args: {
    entry: entryKindEntries[0],
    size: "small",
  },
}

export const ImageSmall: Story = {
  args: {
    entry: entryKindEntries[1],
    size: "small",
  },
}

export const FolderSmall: Story = {
  args: {
    entry: entryKindEntries[2],
    size: "small",
  },
}

export const SheetSmall: Story = {
  args: {
    entry: entryKindEntries[3],
    size: "small",
  },
}

export const DocSmall: Story = {
  args: {
    entry: entryKindEntries[4],
    size: "small",
  },
}

export const VideoSmall: Story = {
  args: {
    entry: entryKindEntries[5],
    size: "small",
  },
}

export const ArchiveSmall: Story = {
  args: {
    entry: entryKindEntries[6],
    size: "small",
  },
}

export const AllKindsAndSizes: StoryObj<{
  component: typeof EntryThumbnailComparison
  args: { entries: readonly EntryThumbnailEntry[] }
}> = {
  render: () => <EntryThumbnailComparison entries={entryKindEntries} />,
}
