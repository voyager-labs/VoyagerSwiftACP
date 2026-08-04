import type { Meta, StoryObj } from "@storybook/react-vite"
import { EntryListRow } from "./EntryListRow"
import type { EntryListRowEntry } from "./EntryListRow"

const entryKindEntries: readonly EntryListRowEntry[] = [
  { id: "e01", name: "IDC20on20The20Hig...tion.pdf", kind: "pdf" },
  { id: "e23", name: "SCR-20251209-noh.png", kind: "image", meta: "775 × 396" },
  { id: "e20", name: "cursor-brand-assets...924 (1)", kind: "folder", count: "3 items" },
  { id: "e53", name: "Voyager waitlist...er.xlsx", kind: "sheet" },
  { id: "e56", name: "privacy-policy-v25.11.27.md", kind: "doc" },
  { id: "e70", name: "Introducing our New Fi...c).mp4", kind: "video", meta: "12:35" },
  { id: "e40", name: "Windsurf-darwin...5.dmg", kind: "archive", meta: "229.2 MB" },
]

const meta = {
  component: EntryListRow,
  tags: ["autodocs"],
  args: {
    entry: entryKindEntries[0],
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
    entry: entryKindEntries[1],
  },
}

export const Folder: Story = {
  args: {
    entry: entryKindEntries[2],
  },
}

export const TableSheet: Story = {
  args: {
    entry: entryKindEntries[3],
  },
}

export const Document: Story = {
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
