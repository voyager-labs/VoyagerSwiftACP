import type { Meta, StoryObj } from "@storybook/react-vite"
import { EntryGrid } from "../../../../packages/file-manager-illustration/src/Domains/Entries/EntryGrid"
import {
  allSelected,
  files,
  imageEntries,
  noSelection,
  selectedInitial,
} from "../../../../packages/file-manager-illustration/src/data/mock-data"

const meta = {
  component: EntryGrid,
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    entries: files,
    selectedEntryIds: selectedInitial,
    onToggleEntry: () => undefined,
  },
} satisfies Meta<typeof EntryGrid>

export default meta
type Story = StoryObj<typeof meta>

export const WithSelection: Story = {}

export const ImagesOnly: Story = {
  args: {
    entries: imageEntries.slice(0, 12),
    selectedEntryIds: ["e23"],
  },
}

export const Empty: Story = {
  args: {
    entries: [],
    selectedEntryIds: noSelection,
  },
}

export const AllSelected: Story = {
  args: {
    selectedEntryIds: allSelected,
  },
}
