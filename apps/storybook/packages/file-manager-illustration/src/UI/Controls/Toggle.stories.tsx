import type { Meta, StoryObj } from "@storybook/react-vite"
import { Toggle } from "./Toggle"

const fn = (): (() => void) => () => {}

const meta = {
  component: Toggle,
  tags: ["autodocs"],
  args: {
    checked: false,
    onChange: fn(),
  },
} satisfies Meta<typeof Toggle>

export default meta
type Story = StoryObj<typeof meta>

export const Off: Story = {}

export const On: Story = {
  args: { checked: true },
}

export const WithLabel: Story = {
  args: { checked: true, label: "Enable dark mode" },
}

export const Small: Story = {
  args: { size: "small", checked: true, label: "Compact" },
}

export const SmallOff: Story = {
  args: { size: "small", label: "Compact" },
}

export const Disabled: Story = {
  args: { disabled: true, label: "Unavailable" },
}

export const DisabledOn: Story = {
  args: { disabled: true, checked: true, label: "Locked on" },
}
