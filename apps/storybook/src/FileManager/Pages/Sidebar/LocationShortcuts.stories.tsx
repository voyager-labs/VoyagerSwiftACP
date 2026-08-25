import type { Meta, StoryObj } from "@storybook/react-vite"
import { LocationShortcuts } from "../../../../packages/file-manager-illustration/src/Pages/Sidebar/LocationShortcuts"
import { locationIconFixtures } from "../../../../packages/file-manager-illustration/src/data/location-icon-fixtures"
import type { LocationShortcut } from "../../../../packages/file-manager-illustration/src/model/types"

const locationShortcuts: readonly LocationShortcut[] = [
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

const meta = {
  component: LocationShortcuts,
  tags: ["autodocs"],
  args: {
    shortcuts: locationShortcuts,
  },
} satisfies Meta<typeof LocationShortcuts>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
