import type { Meta, StoryObj } from "@storybook/react-vite"
import { EntryTile } from "../../../../packages/file-manager-illustration/src/Domains/Entries/EntryTile"
import type { EntryTileEntry } from "../../../../packages/file-manager-illustration/src/Domains/Entries/EntryTile"
import { entryStoryFixtures } from "../../../../packages/file-manager-illustration/src/data/mock-data"

const meta = {
  component: EntryTile,
  tags: ["autodocs"],
  args: {
    entry: entryStoryFixtures.pdfPreview,
    selected: false,
    onToggle: () => undefined,
  },
} satisfies Meta<typeof EntryTile>

export default meta
type Story = StoryObj<typeof meta>

export const Pdf: Story = {}

export const SelectedImage: Story = {
  args: {
    entry: entryStoryFixtures.imagePreview,
    selected: true,
  },
}

export const Folder: Story = {
  args: {
    entry: entryStoryFixtures.folderFallback,
  },
}

export const TableSheet: Story = {
  args: {
    entry: entryStoryFixtures.sheetPreview,
  },
}

export const Document: Story = {
  args: {
    entry: entryStoryFixtures.docPreview,
  },
}

export const Video: Story = {
  args: {
    entry: entryStoryFixtures.videoPreview,
  },
}

export const Archive: Story = {
  args: {
    entry: entryStoryFixtures.archiveFallback,
  },
}
