import type { Meta, StoryObj } from "@storybook/react-vite"
import { Button } from "./Button"
import { IconButton } from "./IconButton"
import { Tooltip } from "./Tooltip"

const meta = {
  component: Tooltip,
  tags: ["autodocs"],
  args: {
    text: "Start New Chat",
    children: <Button>Hover me</Button>,
  },
} satisfies Meta<typeof Tooltip>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const WithIconButton: Story = {
  args: {
    text: "New Chat",
    children: <IconButton aria-label="New Chat">✦</IconButton>,
  },
}
