import type { Meta, StoryObj } from "@storybook/react-vite"
import { Menu, MenuItem } from "../../../../packages/design-foundation/src"

const meta = {
  component: Menu,
  tags: ["autodocs"],
  render: () => (
    <Menu aria-label="Finder-style menu">
      <MenuItem label="Open" />
      <MenuItem label="Move to Trash" shortcut="⌘⌫" />
      <MenuItem label="Paste" disabled />
      <MenuItem label="Delete Permanently" destructive />
    </Menu>
  ),
} satisfies Meta<typeof Menu>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
