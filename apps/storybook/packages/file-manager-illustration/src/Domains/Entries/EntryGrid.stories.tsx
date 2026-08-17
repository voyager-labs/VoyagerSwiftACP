import type { Meta, StoryObj } from "@storybook/react-vite"
import {
  allSelected,
  files,
  imageEntries,
  noSelection,
  selectedInitial,
} from "../../data/mock-data"
import { EntryGrid } from "./EntryGrid"

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
