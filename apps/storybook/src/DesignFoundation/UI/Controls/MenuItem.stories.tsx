import type { Meta, StoryObj } from "@storybook/react-vite"
import { Menu, MenuItem } from "../../../../packages/design-foundation/src"

const meta = {
  component: MenuItem,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <Menu aria-label="Menu item specimen">
        <Story />
      </Menu>
    ),
  ],
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

export const Disabled: Story = {
  args: { label: "Paste", disabled: true },
}
