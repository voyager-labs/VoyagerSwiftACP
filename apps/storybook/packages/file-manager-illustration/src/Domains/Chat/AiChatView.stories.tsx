import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { expect, fn } from "storybook/test"
import { InspectorPane, type InspectorPaneProps } from "../../Layouts/InspectorPane"
import { files } from "../../data/mock-data"
import type { AiChatInputBarActions, ChatSurfaceState } from "../../model/types"
import { AiChatView } from "./AiChatView"
import {
  chatSurfaceCenteredUnconnected,
  chatSurfaceConnectionError,
  chatSurfaceConversation,
  chatSurfaceEmpty,
  chatSurfaceError,
  chatSurfaceHistory,
  chatSurfaceInspectorEmpty,
  chatSurfaceRebind,
  chatSurfaceRecovery,
  chatSurfaceStreaming,
  chatSurfaceUnconnected,
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
    onRebindContext: fn(),
    onStartNewChatFromRebind: fn(),
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

// content-page 전용 component — InspectorPane 헤더/300px 기하 없이 AiChatView를
// 저장소의 full-page review frame(.stage + .content-pane-review) 위에 직접 그린다.
// DESIGN.md: content-page centeredEmpty는 isolated AiChatView specimen으로만 모델링.
function ContentPageAiChatView({
  args,
  state,
}: {
  args: InspectorPaneProps
  state: ChatSurfaceState
}) {
  const [requestText, setRequestText] = useState(args.requestText)

  function handleRequestTextChange(value: string) {
    setRequestText(value)
    args.onRequestTextChange(value)
  }

  return (
    <div data-file-manager-illustration>
      <main className="stage">
        <section className="content-pane-review" aria-label="Chat Content Page">
          <AiChatView
            state={state}
            requestText={requestText}
            onRequestTextChange={handleRequestTextChange}
            onSessionSelected={args.onSessionSelected}
            onOpenSettings={args.onOpenSettings}
            onErrorRecovery={args.onErrorRecovery}
            onRegenerate={args.onRegenerate}
            onRebindContext={args.onRebindContext}
            onStartNewChatFromRebind={args.onStartNewChatFromRebind}
            inputActions={args.chatInputActions}
          />
        </section>
      </main>
    </div>
  )
}

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

// inspector connected empty — surface .empty는 본문 없이 composer만.
export const Empty: Story = {
  args: {
    chatTitle: "New Chat",
    chatSurface: chatSurfaceInspectorEmpty,
  },
  play: async ({ canvas }) => {
    expect(canvas.queryByText("Ask Voyager")).toBeNull()
    expect(canvas.getByRole("textbox", { name: "Chat message" })).toBeEnabled()
    expect(canvas.getByRole("button", { name: "Send" })).toBeDisabled()
  },
}

// content page connected empty — Ask Voyager centered content.
export const CenteredEmpty: Story = {
  args: {
    chatTitle: "Ask Voyager",
    chatSurface: chatSurfaceEmpty,
  },
  render: (args) => (
    <ContentPageAiChatView args={args} state={args.chatSurface as ChatSurfaceState} />
  ),
  play: async ({ canvas }) => {
    expect(canvas.getByText("Ask Voyager")).toBeVisible()
    expect(canvas.queryByLabelText("AI provider status")).toBeNull()
  },
}

// content page unconnected empty — centered content + compactConnectionCTA.
export const CenteredUnconnected: Story = {
  args: {
    chatTitle: "Ask Voyager",
    chatSurface: chatSurfaceCenteredUnconnected,
  },
  render: (args) => (
    <ContentPageAiChatView args={args} state={args.chatSurface as ChatSurfaceState} />
  ),
  play: async ({ args, canvas, userEvent }) => {
    expect(canvas.getByText("Ask Voyager")).toBeVisible()
    expect(canvas.getByText("Connect an AI provider")).toBeVisible()

    await userEvent.click(canvas.getByRole("button", { name: "Open Settings" }))
    await expect(args.onOpenSettings).toHaveBeenCalledTimes(1)
  },
}

export const Unconnected: Story = {
  args: {
    chatTitle: "New Chat",
    chatSurface: chatSurfaceUnconnected,
  },
  play: async ({ args, canvas, userEvent }) => {
    const statusBanner = canvas.getByLabelText("AI provider status")
    const messageInput = canvas.getByRole("textbox", { name: "Chat message" })

    expect(statusBanner.compareDocumentPosition(messageInput) & 4).toBe(4)
    expect(messageInput).not.toBeDisabled()
    expect(canvas.getByRole("button", { name: "Open Settings" })).toBeEnabled()
    expect(canvas.getByRole("combobox", { name: "Model: No models" })).toBeDisabled()
    expect(canvas.getByRole("combobox", { name: "Thinking: No selection" })).toBeDisabled()
    expect(canvas.getByRole("button", { name: "Send" })).toBeDisabled()

    await userEvent.click(canvas.getByRole("button", { name: "Open Settings" }))
    await expect(args.onOpenSettings).toHaveBeenCalledTimes(1)
  },
}

// inspector surface-level error — "Chat unavailable" banner + Retry(errorRecovery).
export const ConnectionError: Story = {
  args: {
    chatTitle: "Review collection PDFs",
    chatSurface: chatSurfaceConnectionError,
  },
  play: async ({ args, canvas, userEvent }) => {
    const statusBanner = canvas.getByLabelText("AI provider status")
    const messageInput = canvas.getByRole("textbox", { name: "Chat message" })

    expect(statusBanner.compareDocumentPosition(messageInput) & 4).toBe(4)
    expect(canvas.getByText("Chat unavailable")).toBeVisible()

    const retry = canvas.getByRole("button", { name: "Retry" })
    expect(retry).toBeEnabled()

    await userEvent.click(retry)
    await expect(args.onErrorRecovery).toHaveBeenCalledTimes(1)
  },
}

// sessionStatus == .rebindRequired — rebind 배너 + 기존 transcript.
export const Rebind: Story = {
  args: {
    chatTitle: "Review collection PDFs",
    chatSurface: chatSurfaceRebind,
  },
  play: async ({ args, canvas, userEvent }) => {
    const banner = canvas.getByLabelText("Rebind required")
    const messageInput = canvas.getByRole("textbox", { name: "Chat message" })

    expect(banner.compareDocumentPosition(messageInput) & 4).toBe(4)
    expect(canvas.getByText("Session needs rebind")).toBeVisible()
    expect(canvas.getByRole("button", { name: "Send" })).toBeDisabled()

    await userEvent.click(canvas.getByRole("button", { name: "Rebind context" }))
    await expect(args.onRebindContext).toHaveBeenCalledTimes(1)

    await userEvent.click(canvas.getByRole("button", { name: "Start new chat" }))
    await expect(args.onStartNewChatFromRebind).toHaveBeenCalledTimes(1)
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
