import type { Meta, StoryObj } from "@storybook/react-vite"
import { SidebarNavItem } from "../../../../packages/design-foundation/src/UI/Navigation/SidebarNavItem"
import type { SidebarTabItem } from "../../../../packages/design-foundation/src/model/ui-types"

const contentTabs: readonly SidebarTabItem[] = [
  { id: "home", label: "Home Page", icon: "home" },
  { id: "directory", label: "Directory", icon: "folder-blue", active: true },
  { id: "collection", label: "Research Collection", icon: "collection" },
] as const

const secondaryLabelItem: SidebarTabItem = {
  id: "directory-tab-short-label",
  label: "Directory Page",
  icon: "folder",
  secondary: "Directory",
}

const meta = {
  component: SidebarNavItem,
  tags: ["autodocs"],
  args: {
    item: contentTabs[0],
  },
} satisfies Meta<typeof SidebarNavItem>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const Active: Story = {
  args: {
    item: contentTabs.find((t) => t.active) ?? contentTabs[0],
  },
}

export const SecondaryLabel: Story = {
  args: {
    item: secondaryLabelItem,
  },
}

export const PinnedUnpinActionRevealed: Story = {
  args: {
    item: { ...contentTabs[0], isPinned: true },
    actionRevealed: true,
  },
}

export const UnpinnedCloseActionRevealed: Story = {
  args: {
    item: contentTabs[0],
    actionRevealed: true,
  },
}
