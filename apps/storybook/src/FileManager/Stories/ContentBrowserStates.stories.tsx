import type { Meta, StoryObj } from "@storybook/react-vite"
import { FileManagerIllustration } from "../../../packages/file-manager-illustration/src/FileManagerIllustration"
import {
  contentBrowserFiles,
  contentBrowserLongNameFiles,
} from "../../../packages/file-manager-illustration/src/data/content-browser-fixtures"
import type { FileManagerInitialPresentation } from "../../../packages/file-manager-illustration/src/model/types"

const contentTabs = [
  { id: "recents", label: "Recents" },
  { id: "downloads", label: "Downloads" },
  { id: "desktop", label: "Desktop" },
  { id: "documents", label: "Documents" },
  { id: "directory", label: "Directory" },
] as const

const defaultPresentation = {
  selectedEntryIds: [],
  viewMode: "grid",
  sidebarOpen: true,
  inspectorOpen: false,
} satisfies FileManagerInitialPresentation

const meta = {
  component: FileManagerIllustration,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  args: {
    files: contentBrowserFiles,
    contentContext: { tabs: contentTabs, activeTabId: "directory" },
    initialPresentation: defaultPresentation,
  },
} satisfies Meta<typeof FileManagerIllustration>

export default meta
type Story = StoryObj<typeof meta>

export const DefaultGrid: Story = {}

export const GridSelection: Story = {
  args: {
    initialPresentation: {
      ...defaultPresentation,
      selectedEntryIds: ["e04", "e05"],
    },
  },
}

export const ListSelection: Story = {
  args: {
    initialPresentation: {
      ...defaultPresentation,
      selectedEntryIds: ["e04"],
      viewMode: "list",
    },
  },
}

export const EmptyGrid: Story = {
  args: {
    files: [],
  },
}

export const LongNamesList: Story = {
  args: {
    files: contentBrowserLongNameFiles,
    initialPresentation: {
      ...defaultPresentation,
      viewMode: "list",
    },
  },
}

export const NarrowSidebarClosed: Story = {
  args: {
    files: contentBrowserLongNameFiles,
    initialPresentation: {
      ...defaultPresentation,
      sidebarOpen: false,
    },
  },
  render: (args) => (
    <div data-file-manager-illustration className="content-browser-narrow-review">
      <FileManagerIllustration {...args} />
    </div>
  ),
}

export const InspectorOpenList: Story = {
  args: {
    initialPresentation: {
      ...defaultPresentation,
      inspectorOpen: true,
      selectedEntryIds: ["e04"],
      viewMode: "list",
    },
  },
}
