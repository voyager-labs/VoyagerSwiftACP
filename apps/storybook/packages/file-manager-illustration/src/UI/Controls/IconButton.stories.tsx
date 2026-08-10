import type { Meta, StoryObj } from "@storybook/react-vite"
import { IconButton } from "./IconButton"

const meta = {
  component: IconButton,
  tags: ["autodocs"],
  args: {
    children: "⌘",
    "aria-label": "Command",
  },
} satisfies Meta<typeof IconButton>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const Bordered: Story = {
  args: { bordered: true },
}

export const Active: Story = {
  args: { active: true },
}

export const Disabled: Story = {
  args: { disabled: true },
}
