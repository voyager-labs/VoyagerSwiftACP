import type { Meta, StoryObj } from "@storybook/react-vite"
import { MenuItem } from "../../../../packages/design-foundation/src/UI/Controls/MenuItem"

const meta = {
  component: MenuItem,
  tags: ["autodocs"],
  args: {
    label: "Open",
  },
} satisfies Meta<typeof MenuItem>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const WithShortcut: Story = {
  args: { label: "Move to Trash", shortcut: "⌘⌫" },
}

export const Destructive: Story = {
  args: { label: "Delete Permanently", destructive: true },
}

export const Disabled: Story = {
  args: { label: "Paste", disabled: true },
}
