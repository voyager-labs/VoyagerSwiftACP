import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { expect, fn } from "storybook/test"
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
  play: async ({ args, canvas, userEvent }) => {
    const input = canvas.getByRole("textbox", { name: "Chat message" })
    await userEvent.type(input, "{enter}")
    await expect(args.actions?.onSubmit).toHaveBeenCalled()
  },
}

export const Selectors: Story = {
  args: {
    presentation: aiChatInputReadyDraft,
  },
  play: async ({ args, canvas, userEvent }) => {
    await userEvent.selectOptions(
      canvas.getByRole("combobox", { name: "Model: GPT-5.2" }),
      "gpt-5.1",
    )
    await userEvent.selectOptions(
      canvas.getByRole("combobox", { name: "Thinking: Medium" }),
      "high",
    )
    await expect(args.actions?.onModelSelected).toHaveBeenCalledWith("gpt-5.1")
    await expect(args.actions?.onThinkingSelected).toHaveBeenCalledWith("high")
  },
}

export const PendingResolution: Story = {
  args: {
    requestText: "Summarize the selected research PDFs.",
    presentation: aiChatInputPendingResolution,
  },
  play: async ({ args, canvas }) => {
    await expect(canvas.getByRole("textbox", { name: "Chat message" })).toBeDisabled()
    await expect(canvas.getByRole("button", { name: "Add attachment" })).toBeDisabled()
    await expect(canvas.getByRole("combobox", { name: "Model: GPT-5.2" })).toBeDisabled()

    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(new File(["fixture"], "blocked-report.pdf", { type: "application/pdf" }))
    canvas
      .getByRole("region", { name: "Chat composer" })
      .dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer }))
    await expect(args.actions?.onAttachmentsDropped).not.toHaveBeenCalled()
  },
}

export const ProcessingNextTurn: Story = {
  args: {
    requestText: "Compare the generated collections when this response finishes.",
    presentation: aiChatInputProcessing,
  },
  play: async ({ args, canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Stop" }))
    await expect(args.actions?.onStop).toHaveBeenCalled()
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
  play: async ({ args, canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Remove Fitchett2014.pdf" }))
    await expect(args.actions?.onRemoveContextItem).toHaveBeenCalledWith("fitchett-2014")

    const composer = canvas.getByRole("region", { name: "Chat composer" })
    const dataTransfer = new DataTransfer()
    const file = new File(["fixture"], "dropped-report.pdf", { type: "application/pdf" })
    dataTransfer.items.add(file)
    dataTransfer.setData(
      "text/uri-list",
      "https://example.com/notes.pdf\n# browser comment\nnot-a-url",
    )
    composer.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer }))
    await expect(args.actions?.onAttachmentsDropped).toHaveBeenCalled()
    await expect(args.actions?.onAttachmentsDropped).toHaveBeenCalledWith(
      expect.objectContaining({
        files: [file],
        urls: [new URL("https://example.com/notes.pdf")],
      }),
    )
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
