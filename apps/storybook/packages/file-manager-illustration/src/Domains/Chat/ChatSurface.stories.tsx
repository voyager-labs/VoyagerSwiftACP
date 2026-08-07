import type { Meta, StoryObj } from "@storybook/react-vite"
import { InspectorPane } from "../../Layouts/InspectorPane"
import { files } from "../../data/mock-data"
import {
  chatSurfaceConversation,
  chatSurfaceEmpty,
  chatSurfaceError,
  chatSurfaceHistory,
  chatSurfaceStreaming,
} from "./chat-fixtures"

// 채팅 도메인 스토리 — InspectorPane 헤더 + ChatSurface 본문의 상태 매트릭스.
// 각 상태는 네이티브 AiChatViewPresentation에 대응한다.

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
    onRequestTextChange: () => {},
    onOpenChatHistory: () => {},
    onOpenNewChat: () => {},
    onCloseChat: () => {},
    onSessionSelected: () => {},
    onOpenSettings: () => {},
    onErrorRecovery: () => {},
    onRegenerate: () => {},
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
