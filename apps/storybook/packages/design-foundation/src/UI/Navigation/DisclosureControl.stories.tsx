import type { Meta, StoryObj } from "@storybook/react-vite"
import { DisclosureControl } from "./DisclosureControl"

const fn = (): (() => void) => () => {}

const meta = {
  component: DisclosureControl,
  tags: ["autodocs"],
  args: {
    expanded: false,
    onToggle: fn(),
    children: "Customize per view",
  },
} satisfies Meta<typeof DisclosureControl>

export default meta
type Story = StoryObj<typeof meta>

export const Collapsed: Story = {}

export const Expanded: Story = {
  args: { expanded: true },
}

export const ButtonStyle: Story = {
  args: { buttonStyle: true, children: "More options" },
}
