import type { Meta, StoryObj } from "@storybook/react-vite"
import { expect, within } from "storybook/test"
import type { SidebarTabItem } from "../model/types"
import { SidebarSection } from "./SidebarSection"

const pinnedTabs: readonly SidebarTabItem[] = [
  { id: "recents", label: "Recents", icon: "folder", isPinned: true },
  { id: "downloads", label: "Downloads", icon: "folder", isPinned: true },
  { id: "desktop", label: "Desktop", icon: "folder", isPinned: true },
  { id: "documents", label: "Documents", icon: "folder", isPinned: true },
  { id: "projects", label: "Projects", icon: "folder", isPinned: true },
] as const

const contentTabs: readonly SidebarTabItem[] = [
  { id: "home", label: "Home Page", icon: "home" },
  { id: "directory", label: "Directory", icon: "folder-blue", active: true },
  { id: "collection", label: "Research Collection", icon: "collection" },
  { id: "ai-chat", label: "AI Chat", icon: "chat" },
] as const

const meta = {
  component: SidebarSection,
  tags: ["autodocs"],
} satisfies Meta<typeof SidebarSection>

export default meta
type Story = StoryObj<typeof meta>

export const Pinned: Story = {
  args: {
    title: "Favorites",
    items: pinnedTabs,
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByRole("button", { name: "Collapse favorites" })).toHaveAttribute(
      "aria-expanded",
      "true",
    )
  },
}

export const ContentTabs: Story = {
  args: {
    title: "Pages",
    items: contentTabs,
  },
}
