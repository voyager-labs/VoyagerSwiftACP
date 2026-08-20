import type { Meta, StoryObj } from "@storybook/react-vite"
import { Sidebar } from "../../../packages/file-manager-illustration/src/Layouts/Sidebar"
import { locationIconFixtures } from "../../../packages/file-manager-illustration/src/data/location-icon-fixtures"
import type { SidebarTabItem } from "../../../packages/file-manager-illustration/src/model/types"

const locationShortcuts = [
  { id: "home", label: "Home", symbolName: "house", iconSrc: locationIconFixtures.home },
  {
    id: "icloud-drive",
    label: "iCloud Drive",
    symbolName: "icloud",
    iconSrc: locationIconFixtures.iCloudDrive,
  },
  {
    id: "google-drive",
    label: "Google Drive",
    symbolName: "folder",
    iconSrc: locationIconFixtures.googleDrive,
  },
  {
    id: "macintosh-hd",
    label: "Macintosh HD",
    symbolName: "internaldrive",
    iconSrc: locationIconFixtures.macintoshHD,
  },
  {
    id: "external-drive",
    label: "External Drive",
    symbolName: "externaldrive",
    iconSrc: locationIconFixtures.externalDrive,
  },
  { id: "trash", label: "Trash", symbolName: "trash", iconSrc: locationIconFixtures.trash },
] as const

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
] as const

const longLabelTabs: readonly SidebarTabItem[] = [
  {
    id: "long-pinned-tab",
    label: "A pinned tab with a deliberately long label for truncation review",
    icon: "folder",
    isPinned: true,
  },
  {
    id: "long-unpinned-tab",
    label: "An unpinned tab with a deliberately long label for truncation review",
    icon: "collection",
  },
] as const

const meta = {
  component: Sidebar,
  tags: ["autodocs"],
  args: {
    locationShortcuts,
    pinnedTabs,
    contentTabs,
    standalone: true,
    onLocationSelect: () => {},
    onTabSelect: () => {},
    onTabUnpin: () => {},
    onTabClose: () => {},
    onNewTab: () => {},
  },
} satisfies Meta<typeof Sidebar>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const Mixed: Story = {
  args: {
    contentTabs: contentTabs.map((item) => ({ ...item, active: item.id === "home" })),
  },
}

export const ActionRevealed: Story = {
  args: {
    revealTabActions: true,
  },
}

export const Empty: Story = {
  args: {
    locationShortcuts: [],
    pinnedTabs: [],
    contentTabs: [],
  },
}

export const LongLabel: Story = {
  args: {
    pinnedTabs: [longLabelTabs[0]],
    contentTabs: [longLabelTabs[1]],
    revealTabActions: true,
  },
}
