import type { Meta, StoryObj } from "@storybook/react-vite"
import { ChatMessageBubble } from "./ChatMessageBubble"

const meta = {
  component: ChatMessageBubble,
  tags: ["autodocs"],
  args: {
    children: "Summarize the selected research PDFs and group recurring file organization themes.",
  },
} satisfies Meta<typeof ChatMessageBubble>

export default meta
type Story = StoryObj<typeof meta>

export const Short: Story = {}

export const Long: Story = {
  args: {
    children:
      "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014, file-organization taxonomies, and usability evaluation methods. Want me to create a collection for each theme and surface likely duplicates across the citation group?",
  },
}
