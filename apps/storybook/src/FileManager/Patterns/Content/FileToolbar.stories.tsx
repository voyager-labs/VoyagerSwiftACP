import type { Meta, StoryObj } from "@storybook/react-vite"
import { FileToolbar } from "../../../../packages/file-manager-illustration/src/Patterns/Content/FileToolbar"

const meta = {
  component: FileToolbar,
  tags: ["autodocs"],
  args: {
    title: "Directory",
    content: "directory" as const,
    viewMode: "grid",
    showSidebarButton: false,
    onViewModeChange: () => {},
    onToggleSidebar: () => {},
  },
} satisfies Meta<typeof FileToolbar>

export default meta
type Story = StoryObj<typeof meta>

export const BothPanesOpen: Story = {}

export const FocusMode: Story = {
  args: {
    showSidebarButton: true,
  },
}

export const ListView: Story = {
  args: {
    viewMode: "list",
  },
}
