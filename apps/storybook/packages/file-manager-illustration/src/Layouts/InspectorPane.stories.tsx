import type { Meta, StoryObj } from "@storybook/react-vite"
import { files } from "../data/mock-data"
import { InspectorPane } from "./InspectorPane"

const primaryEntry = files[0]

const meta = {
  component: InspectorPane,
  tags: ["autodocs"],
  args: {
    chatHeader: "sessions" as const,
    requestText: "",
    selectedEntries: files.slice(0, 5),
    primaryEntry,
    chatTitle: "Chat History",
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
  },
}
