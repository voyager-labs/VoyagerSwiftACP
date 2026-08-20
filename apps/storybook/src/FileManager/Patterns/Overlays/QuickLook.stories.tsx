import type { Meta, StoryObj } from "@storybook/react-vite"
import { QuickLook } from "../../../../packages/file-manager-illustration/src/Patterns/Overlays/QuickLook"
import { entryStoryFixtures } from "../../../../packages/file-manager-illustration/src/data/mock-data"

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
