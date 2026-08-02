import type { Meta, StoryObj } from "@storybook/react-vite"
import { files } from "../data/mock-data"
import { ChatPane } from "./ChatPane"

const primaryEntry = files[0]

const meta = {
  component: ChatPane,
  tags: ["autodocs"],
  args: {
    requestText: "",
    selectedEntries: files.slice(0, 5),
    primaryEntry,
    onRequestTextChange: () => {},
  },
} satisfies Meta<typeof ChatPane>

export default meta
type Story = StoryObj<typeof meta>

export const EmptyPrompt: Story = {}

export const DraftPrompt: Story = {
  args: {
    requestText:
      "Summarize the selected research PDFs and group recurring file organization themes.",
  },
}
