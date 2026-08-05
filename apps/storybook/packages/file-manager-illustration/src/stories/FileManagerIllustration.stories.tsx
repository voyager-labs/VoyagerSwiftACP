import type { Meta, StoryObj } from "@storybook/react-vite"
import { expect, userEvent, within } from "storybook/test"
import { FileManagerIllustration } from "../FileManagerIllustration"
import { publicFiles } from "../data/mock-data"

const defaultTabs = [
  { id: "recents", label: "Recents" },
  { id: "downloads", label: "Downloads" },
  { id: "desktop", label: "Desktop" },
  { id: "documents", label: "Documents" },
  { id: "projects", label: "Projects" },
  { id: "home", label: "Home Page" },
  { id: "directory", label: "Directory" },
  { id: "collection", label: "Research Collection" },
  { id: "ai-chat", label: "AI Chat" },
] as const

const meta = {
  component: FileManagerIllustration,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
} satisfies Meta<typeof FileManagerIllustration>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  args: {
    files: publicFiles,
    chatMessages: [
      { role: "user", paragraph: "Show me the budget files" },
      { role: "assistant", paragraph: "Here are the spreadsheet files I found." },
    ],
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
  },
  play: async ({ canvasElement }) => {
    const gridBtn = within(canvasElement).getByRole("button", { name: "Grid view" })
    await userEvent.click(gridBtn)
    const listBtn = within(canvasElement).getByRole("button", { name: "List view" })
    await userEvent.click(listBtn)
  },
}

export const ListView: Story = {
  args: {
    files: publicFiles,
    chatMessages: [],
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(within(canvasElement).getByRole("button", { name: "List view" }))
    const entry = canvasElement.querySelector(".entry-list-row")
    if (entry instanceof HTMLElement) await userEvent.click(entry)
  },
}

export const FocusMode: Story = {
  args: {
    files: publicFiles,
    chatMessages: [],
    contentContext: { tabs: defaultTabs, activeTabId: "directory" },
  },
  play: async ({ canvasElement }) => {
    const sidebarBtn = within(canvasElement).getByRole("button", { name: "Hide Sidebar" })
    await userEvent.click(sidebarBtn)
    await userEvent.click(within(canvasElement).getByRole("button", { name: "Show Sidebar" }))
    await userEvent.click(within(canvasElement).getByRole("button", { name: "New Chat" }))
    await userEvent.click(within(canvasElement).getByRole("button", { name: "Close AI Chat" }))
  },
}

/** Replaces obsolete PropertiesMode — AI Chat as primary content. */
export const AIChatPrimary: Story = {
  args: {
    files: publicFiles,
    chatMessages: [],
    contentContext: { tabs: defaultTabs, activeTabId: "ai-chat" },
  },
  play: async ({ canvasElement }) => {
    const chatArea = canvasElement.querySelector(
      '[data-file-manager-illustration-workflow="ai-chat-content"]',
    )
    expect(chatArea).toBeInTheDocument()
    expect(within(canvasElement).queryByRole("region", { name: "Entries" })).not.toBeInTheDocument()
    expect(
      within(canvasElement).queryByRole("complementary", { name: "Context Pane" }),
    ).not.toBeInTheDocument()
  },
}

export const Home: Story = {
  args: {
    files: [],
    chatMessages: [],
    contentContext: { tabs: defaultTabs, activeTabId: "home" },
  },
  play: async ({ canvasElement }) => {
    const home = within(canvasElement).getByRole("region", { name: "Home" })
    expect(home).toBeInTheDocument()
  },
}
