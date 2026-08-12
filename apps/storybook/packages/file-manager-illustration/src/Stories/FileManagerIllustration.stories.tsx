import type { Meta, StoryObj } from "@storybook/react-vite"
import { expect, fn, userEvent, within } from "storybook/test"
import {
  chatSurfaceConversation,
  chatSurfaceEmpty,
  chatSurfaceError,
  chatSurfaceHistory,
  chatSurfaceRecovery,
  chatSurfaceStreaming,
} from "../Domains/Chat/chat-fixtures"
import { FileManagerIllustration } from "../FileManagerIllustration"
import { publicFiles } from "../data/mock-data"
import type { AiChatInputBarActions } from "../model/types"

const defaultTabs = [
  { id: "recents", label: "Recents" },
  { id: "downloads", label: "Downloads" },
  { id: "desktop", label: "Desktop" },
  { id: "documents", label: "Documents" },
  { id: "projects", label: "Projects" },
  { id: "home", label: "Home Page" },
  { id: "directory", label: "Directory" },
  { id: "collection", label: "Research Collection" },
] as const

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
  component: FileManagerIllustration,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  args: { chatInputActions },
} satisfies Meta<typeof FileManagerIllustration>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
  },
  play: async ({ canvasElement }) => {
    const gridBtn = within(canvasElement).getByRole("button", { name: "Grid view" })
    gridBtn.focus()
    await userEvent.click(gridBtn)
    const listBtn = within(canvasElement).getByRole("button", { name: "List view" })
    await userEvent.click(listBtn)
  },
}

export const ListView: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
  },
  play: async ({ canvasElement }) => {
    const listBtn = within(canvasElement).getByRole("button", { name: "List view" })
    listBtn.focus()
    await userEvent.click(listBtn)
    const entry = canvasElement.querySelector(".entry-list-row")
    if (entry instanceof HTMLElement) await userEvent.click(entry)
  },
}

export const FocusMode: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(within(canvasElement).getByRole("button", { name: "New Chat" }))
    await userEvent.click(within(canvasElement).getByRole("button", { name: "Close AI Chat" }))
  },
}

export const Home: Story = {
  args: {
    files: [],
    contentContext: { tabs: defaultTabs, activeTabId: "home" },
  },
  play: async ({ canvasElement }) => {
    const home = within(canvasElement).getByRole("region", { name: "Home" })
    expect(home).toBeInTheDocument()
  },
}

// VOY-721: Inspector Chat 상태 매트릭스를 root composition에서 재현.

export const ChatHistory: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
    chatSurface: chatSurfaceHistory,
  },
}

export const ChatConversation: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
    chatSurface: chatSurfaceConversation,
  },
}

export const ChatEmpty: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
    chatSurface: chatSurfaceEmpty,
  },
}

export const ChatStreaming: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
    chatSurface: chatSurfaceStreaming,
  },
}

export const ChatErrorState: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
    chatSurface: chatSurfaceError,
  },
}

export const ChatRecovery: Story = {
  args: {
    files: publicFiles,
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
    chatSurface: chatSurfaceRecovery,
    chatOnErrorRecovery: fn(),
  },
  play: async ({ args, canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Retry" }))
    await expect(args.chatOnErrorRecovery).toHaveBeenCalled()
  },
}
