import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { fn } from "storybook/test"
import type { AiChatInputBarActions } from "../../model/types"
import { AiChatInputBar } from "./AiChatInputBar"
import {
  aiChatInputModelUnavailable,
  aiChatInputPendingResolution,
  aiChatInputProcessing,
  aiChatInputProcessingStopDisabled,
  aiChatInputReadyDraft,
  aiChatInputReadyEmpty,
  aiChatInputWithContext,
} from "./ai-chat-input-fixtures"

const inputActions = {
  onAddAttachment: fn(),
  onModelSelected: fn(),
  onThinkingSelected: fn(),
  onSubmit: fn(),
  onStop: fn(),
  onRemoveContextItem: fn(),
  onAttachmentsDropped: fn(),
} satisfies AiChatInputBarActions

const meta = {
  component: AiChatInputBar,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  decorators: [
    (Story, context) => (
      <div className="fm-ai-chat-input-story-canvas">
        <div
          className={`fm-ai-chat-input-story-frame${context.parameters.inputWidth === "narrow" ? " is-narrow" : ""}`}
        >
          <Story />
        </div>
      </div>
    ),
  ],
  args: {
    requestText: "",
    onRequestTextChange: fn(),
    presentation: aiChatInputReadyEmpty,
    actions: inputActions,
  },
  render: function Render(args) {
    const [requestText, setRequestText] = useState(args.requestText)

    function handleRequestTextChange(value: string) {
      setRequestText(value)
      args.onRequestTextChange(value)
    }

    return (
      <AiChatInputBar
        {...args}
        requestText={requestText}
        onRequestTextChange={handleRequestTextChange}
      />
    )
  },
} satisfies Meta<typeof AiChatInputBar>

export default meta
type Story = StoryObj<typeof meta>

export const ReadyEmpty: Story = {}

export const ReadyDraft: Story = {
  args: {
    requestText: "Group these entries by research theme and surface likely duplicates.",
    presentation: aiChatInputReadyDraft,
  },
}

export const PendingResolution: Story = {
  args: {
    requestText: "Summarize the selected research PDFs.",
    presentation: aiChatInputPendingResolution,
  },
}

export const ProcessingNextTurn: Story = {
  args: {
    requestText: "Compare the generated collections when this response finishes.",
    presentation: aiChatInputProcessing,
  },
}

export const ProcessingStopDisabled: Story = {
  args: {
    presentation: aiChatInputProcessingStopDisabled,
  },
}

export const ModelUnavailable: Story = {
  args: {
    requestText: "Create a collection from these files.",
    presentation: aiChatInputModelUnavailable,
  },
}

export const WithRequestContext: Story = {
  args: {
    requestText: "Compare duplicate references across these documents.",
    presentation: aiChatInputWithContext,
  },
}

export const MultilineMaximumHeight: Story = {
  args: {
    requestText:
      "Summarize the selected research PDFs.\n\nGroup recurring organization themes.\n\nSurface duplicate citations and explain why they overlap.\n\nKeep the result concise but include the source filenames.\n\nSuggest a collection name for each theme.",
    presentation: aiChatInputReadyDraft,
  },
}

export const NarrowMinimumWidth: Story = {
  parameters: { inputWidth: "narrow" },
  args: {
    requestText: "Group these files by theme.",
    presentation: aiChatInputReadyDraft,
  },
}
