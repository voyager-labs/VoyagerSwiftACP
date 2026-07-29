import type { Meta, StoryObj } from "@storybook/react-vite"
import { Button } from "./Button"

const meta = {
  component: Button,
  tags: ["autodocs"],
  args: {
    children: "Button",
  },
} satisfies Meta<typeof Button>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const Primary: Story = {
  args: { variant: "primary", children: "Primary" },
}

export const Subtle: Story = {
  args: { variant: "subtle", children: "Subtle" },
}

export const Destructive: Story = {
  args: { variant: "destructive", children: "Delete" },
}

export const Loading: Story = {
  args: { loading: true, children: "Saving…" },
}

export const Pill: Story = {
  args: { pill: true, children: "Pill" },
}
