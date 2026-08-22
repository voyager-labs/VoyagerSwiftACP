import type { Meta, StoryObj } from "@storybook/react-vite"
import { EntryListRow } from "../../../../packages/file-manager-illustration/src/Domains/Entries/EntryListRow"
import type { EntryListRowEntry } from "../../../../packages/file-manager-illustration/src/Domains/Entries/EntryListRow"
import { entryStoryFixtures } from "../../../../packages/file-manager-illustration/src/data/mock-data"

const meta = {
  component: EntryListRow,
  tags: ["autodocs"],
  args: {
    entry: entryStoryFixtures.pdfPreview,
    selected: false,
    onToggle: () => undefined,
  },
} satisfies Meta<typeof EntryListRow>

export default meta
type Story = StoryObj<typeof meta>

export const Pdf: Story = {}

export const Selected: Story = {
  args: {
    selected: true,
  },
}

export const Image: Story = {
  args: {
    entry: entryStoryFixtures.imagePreview,
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
