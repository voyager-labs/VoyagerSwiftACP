import type { Meta, StoryObj } from "@storybook/react-vite"
import { EntryList } from "../../../../packages/file-manager-illustration/src/Domains/Entries/EntryList"
import {
  entryKindEntries,
  entryStoryFixtures,
  files,
  selectedInitial,
} from "../../../../packages/file-manager-illustration/src/data/mock-data"

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
