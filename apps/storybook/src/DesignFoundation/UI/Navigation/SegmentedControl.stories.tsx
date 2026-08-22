import type { Meta, StoryObj } from "@storybook/react-vite"
import { SegmentedControl } from "../../../../packages/design-foundation/src/UI/Navigation/SegmentedControl"

const fn = (): ((value: string) => void) => () => {}

const meta = {
  component: SegmentedControl,
  tags: ["autodocs"],
  args: {
    options: [
      { value: "small", label: "Small" },
      { value: "medium", label: "Medium" },
      { value: "large", label: "Large" },
    ],
    value: "medium",
    onChange: fn(),
  },
} satisfies Meta<typeof SegmentedControl>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const FirstSelected: Story = {
  args: { value: "small" },
}

export const LastSelected: Story = {
  args: { value: "large" },
}

export const TwoOptions: Story = {
  args: {
    options: [
      { value: "list", label: "List" },
      { value: "icon", label: "Icon" },
    ],
    value: "list",
  },
}
