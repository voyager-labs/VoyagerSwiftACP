import type { Meta, StoryObj } from "@storybook/react-vite"
import {
  chatSurfaceConversation,
  chatSurfaceHistory,
} from "../../../../packages/file-manager-illustration/src/Domains/Chat/chat-fixtures"
import { InspectorPane } from "../../../../packages/file-manager-illustration/src/Pages/Inspector/InspectorPane"

const meta = {
  component: InspectorPane,
  tags: ["autodocs"],
  args: {
    chatHeader: "sessions" as const,
    requestText: "",
    chatTitle: "Chat History",
    chatSurface: chatSurfaceHistory,
    onRequestTextChange: () => {},
    onOpenChatHistory: () => {},
    onOpenNewChat: () => {},
    onCloseChat: () => {},
  },
} satisfies Meta<typeof InspectorPane>

export default meta
type Story = StoryObj<typeof meta>

export const ChatHistory: Story = {}

export const Conversation: Story = {
  args: {
    chatHeader: "chat" as const,
    chatTitle: "Review collection PDFs",
    chatSurface: chatSurfaceConversation,
  },
}
