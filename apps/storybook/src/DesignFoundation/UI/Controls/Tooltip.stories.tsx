import type { Meta, StoryObj } from "@storybook/react-vite"
import { SFSymbol } from "../../../../packages/design-foundation/src/Foundations/SFSymbol"
import { Button } from "../../../../packages/design-foundation/src/UI/Controls/Button"
import { IconButton } from "../../../../packages/design-foundation/src/UI/Controls/IconButton"
import { Tooltip } from "../../../../packages/design-foundation/src/UI/Controls/Tooltip"

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
    children: (
      <IconButton aria-label="New Chat">
        <SFSymbol name="sidebar.trailing" size={16} />
      </IconButton>
    ),
  },
}
