import type { Meta, StoryObj } from "@storybook/react-vite"
import type { LocationShortcut } from "../types"
import { LocationShortcuts } from "./LocationShortcuts"

const locationShortcuts: readonly LocationShortcut[] = [
  { id: "local-entries", label: "Local Entries", glyph: "▣" },
  { id: "cloud-entries", label: "Cloud Entries", glyph: "☁" },
  { id: "trash", label: "Trash", glyph: "⌫" },
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
