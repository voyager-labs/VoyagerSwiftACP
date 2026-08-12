import type { Meta, StoryObj } from "@storybook/react-vite"
import { AiChatUserMessageBubble } from "./AiChatUserMessageBubble"

const meta = {
  component: AiChatUserMessageBubble,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="fm-chat-message-story-frame">
        <div className="chat-message-user">
          <div className="chat-user-bubble-frame">
            <Story />
          </div>
        </div>
      </div>
    ),
  ],
  args: {
    children: "Summarize the selected research PDFs and group recurring file organization themes.",
  },
} satisfies Meta<typeof AiChatUserMessageBubble>

export default meta
type Story = StoryObj<typeof meta>

export const Short: Story = {}

export const Long: Story = {
  args: {
    children:
      "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014, file-organization taxonomies, and usability evaluation methods. Want me to create a collection for each theme and surface likely duplicates across the citation group?",
  },
}

export const CopyFeedback: Story = {
  args: {
    copyFeedback: "copied",
  },
}

export const CopyFailure: Story = {
  args: {
    copyFeedback: "failed",
  },
}
