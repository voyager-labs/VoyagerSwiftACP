import type { Meta, StoryObj } from "@storybook/react-vite"
import { entryKindEntries } from "../mock-data"
import { QuickLook } from "./QuickLook"

const meta = {
  component: QuickLook,
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    entry: entryKindEntries[1],
  },
} satisfies Meta<typeof QuickLook>

export default meta
type Story = StoryObj<typeof meta>

export const ImageIcon: Story = {}

export const PdfIcon: Story = {
  args: {
    entry: entryKindEntries[0],
  },
}
