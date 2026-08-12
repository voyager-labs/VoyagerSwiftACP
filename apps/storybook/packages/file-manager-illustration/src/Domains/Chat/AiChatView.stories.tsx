import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { expect, fn } from "storybook/test"
import { InspectorPane } from "../../Layouts/InspectorPane"
import { files } from "../../data/mock-data"
import type { AiChatInputBarActions } from "../../model/types"
import {
  chatSurfaceConversation,
  chatSurfaceEmpty,
  chatSurfaceError,
  chatSurfaceHistory,
  chatSurfaceRecovery,
  chatSurfaceStreaming,
} from "./chat-fixtures"

// 채팅 도메인 스토리 — InspectorPane 헤더 + AiChatView 본문의 상태 매트릭스.
// 각 상태는 네이티브 AiChatViewPresentation에 대응한다.

const chatInputActions = {
  onAddAttachment: fn(),
  onModelSelected: fn(),
  onThinkingSelected: fn(),
  onSubmit: fn(),
  onStop: fn(),
  onRemoveContextItem: fn(),
  onAttachmentsDropped: fn(),
} satisfies AiChatInputBarActions

const meta = {
  component: InspectorPane,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  args: {
    chatHeader: "chat",
    requestText: "",
    selectedEntries: files.slice(0, 3),
    primaryEntry: files[0],
    chatTitle: "Review collection PDFs",
    onRequestTextChange: fn(),
    onOpenChatHistory: fn(),
    onOpenNewChat: fn(),
    onCloseChat: fn(),
    onSessionSelected: fn(),
    onOpenSettings: fn(),
    onErrorRecovery: fn(),
    onRegenerate: fn(),
    chatInputActions,
  },
  render: function Render(args) {
    const [requestText, setRequestText] = useState(args.requestText)

    function handleRequestTextChange(value: string) {
      setRequestText(value)
      args.onRequestTextChange(value)
    }

    return (
      <InspectorPane
        {...args}
        requestText={requestText}
        onRequestTextChange={handleRequestTextChange}
      />
    )
  },
} satisfies Meta<typeof InspectorPane>

export default meta
type Story = StoryObj<typeof meta>

export const History: Story = {
  args: {
    chatHeader: "sessions",
    chatTitle: "Chat History",
    chatSurface: chatSurfaceHistory,
  },
}

export const Conversation: Story = {
  args: {
    chatSurface: chatSurfaceConversation,
  },
}

export const Empty: Story = {
  args: {
    chatSurface: chatSurfaceEmpty,
  },
}

export const Streaming: Story = {
  args: {
    chatSurface: chatSurfaceStreaming,
  },
}

export const ErrorState: Story = {
  args: {
    chatSurface: chatSurfaceError,
  },
}

export const Recovery: Story = {
  args: {
    chatSurface: chatSurfaceRecovery,
  },
  play: async ({ args, canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Retry" }))
    await expect(args.onErrorRecovery).toHaveBeenCalled()
  },
}
