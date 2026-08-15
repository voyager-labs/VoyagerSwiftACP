import type { Meta, StoryObj } from "@storybook/react-vite"
import { entryStoryFixtures } from "../../data/mock-data"
import { QuickLook } from "./QuickLook"

const meta = {
  component: QuickLook,
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    entry: entryStoryFixtures.imagePreview,
  },
} satisfies Meta<typeof QuickLook>

export default meta
type Story = StoryObj<typeof meta>

export const ImageThumbnail: Story = {}

export const PdfThumbnail: Story = {
  args: {
    entry: entryStoryFixtures.pdfPreview,
  },
}
