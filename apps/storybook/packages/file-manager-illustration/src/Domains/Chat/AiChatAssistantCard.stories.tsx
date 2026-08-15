import type { Meta, StoryObj } from "@storybook/react-vite"
import { AiChatAssistantCard } from "./AiChatAssistantCard"
import { AiChatAssistantMarkdownText } from "./AiChatAssistantMarkdownText"
import { resolveAiChatAssistantPresentation } from "./AiChatAssistantPresentation"
import { chatRichMarkdownContent } from "./chat-fixtures"

const meta = {
  component: AiChatAssistantCard,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="fm-chat-message-story-frame">
        <div className="chat-message-assistant" data-chat-role="assistant">
          <Story />
        </div>
      </div>
    ),
  ],
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      isProcessing: true,
    }),
  },
} satisfies Meta<typeof AiChatAssistantCard>

export default meta
type Story = StoryObj<typeof meta>

// AiChatAssistantBodyPresentation 상태 기기 매트릭스.

export const Waiting: Story = {
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      thinkingLabel: "Thinking",
      activityStatusLabel: "Reading 6 PDFs",
      isProcessing: true,
    }),
  },
}

export const Processing: Story = {
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      content:
        "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014 and file-organization",
      isProcessing: true,
    }),
  },
}

export const Completed: Story = {
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      content:
        "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014, file-organization taxonomies, and usability evaluation methods.",
      headerPresentation: "completedHistorical",
    }),
  },
}

export const StructuredResponse: Story = {
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      content: [
        "## Research themes",
        "",
        "I reviewed 6 PDFs and found three recurring organization patterns:",
        "",
        "- Citation networks around Fitchett 2014",
        "- File-organization taxonomies",
        "- Usability evaluation methods",
        "",
        "1. Keep the longer survey in the primary collection.",
        "2. Flag the overlapping paper for review.",
        "",
        "```",
        "collection: Research methods",
        "duplicates: 2",
        "```",
      ].join("\n"),
      headerPresentation: "completedHistorical",
    }),
  },
}

export const RichMarkdown: Story = {
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      content: chatRichMarkdownContent,
      headerPresentation: "completedHistorical",
    }),
  },
}

export const CopyFeedback: Story = {
  render: () => (
    <AiChatAssistantMarkdownText content={chatRichMarkdownContent} copyFeedback="copied" />
  ),
}

export const PartialFailure: Story = {
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      content: "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014 and",
      failure: "Connection lost while generating the response.",
    }),
  },
}

export const TerminalFailure: Story = {
  args: {
    presentation: resolveAiChatAssistantPresentation({
      title: "Assistant",
      isProcessing: true,
      failure: "Failed to reach the AI provider. Check the connection and try again.",
    }),
  },
}
