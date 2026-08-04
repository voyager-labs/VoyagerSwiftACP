import type { Meta, StoryObj } from "@storybook/react-vite"
import type { LocationShortcut } from "../model/types"
import { LocationShortcuts } from "./LocationShortcuts"

const locationShortcuts: readonly LocationShortcut[] = [
  { id: "local-entries", label: "Local Entries", symbolName: "rectangle.3.group" },
  { id: "cloud-entries", label: "Cloud Entries", symbolName: "icloud" },
  { id: "trash", label: "Trash", symbolName: "trash" },
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
