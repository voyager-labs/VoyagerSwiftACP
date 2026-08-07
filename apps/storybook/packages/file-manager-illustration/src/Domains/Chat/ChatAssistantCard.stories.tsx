import type { Meta, StoryObj } from "@storybook/react-vite"
import { ChatAssistantCard } from "./ChatAssistantCard"

const meta = {
  component: ChatAssistantCard,
  tags: ["autodocs"],
  args: {
    title: "Assistant",
  },
} satisfies Meta<typeof ChatAssistantCard>

export default meta
type Story = StoryObj<typeof meta>

// AiChatAssistantBodyPresentation 상태 기기 매트릭스.

export const Waiting: Story = {
  args: {
    title: "Assistant",
    thinkingLabel: "Thinking",
    activityStatusLabel: "Reading 6 PDFs",
    isProcessing: true,
  },
}

export const Processing: Story = {
  args: {
    title: "Assistant",
    content:
      "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014 and file-organization",
    isProcessing: true,
  },
}

export const Completed: Story = {
  args: {
    title: "Assistant",
    content:
      "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014, file-organization taxonomies, and usability evaluation methods.",
    headerPresentation: "completedHistorical",
  },
}

export const PartialFailure: Story = {
  args: {
    title: "Assistant",
    content: "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014 and",
    failure: "Connection lost while generating the response.",
  },
}

export const TerminalFailure: Story = {
  args: {
    title: "Assistant",
    isProcessing: true,
    failure: "Failed to reach the AI provider.",
  },
}
