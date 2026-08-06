import type { Meta, StoryObj } from "@storybook/react-vite"
import { entryKindEntries, entryStoryFixtures, files, selectedInitial } from "../data/mock-data"
import { EntryList } from "./EntryList"

const meta = {
  component: EntryList,
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    entries: files,
    selectedEntryIds: selectedInitial,
    onToggleEntry: () => undefined,
  },
} satisfies Meta<typeof EntryList>

export default meta
type Story = StoryObj<typeof meta>

export const WithSelection: Story = {}

export const AllEntryKinds: Story = {
  args: {
    entries: entryKindEntries,
    selectedEntryIds: [entryStoryFixtures.imageFallback.id],
  },
}

export const Empty: Story = {
  args: {
    entries: [],
    selectedEntryIds: [],
  },
}
