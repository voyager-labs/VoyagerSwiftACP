import type { Meta, StoryObj } from "@storybook/react-vite"
import { TextField } from "./TextField"

const meta = {
  component: TextField,
  tags: ["autodocs"],
  args: {
    placeholder: "Enter text…",
  },
} satisfies Meta<typeof TextField>

export default meta
type Story = StoryObj<typeof meta>

export const Placeholder: Story = {}

export const Filled: Story = {
  args: { value: "Quarterly Report.pdf" },
}

export const Multiline: Story = {
  args: {
    multiline: true,
    rows: 4,
    value: "Summarize the key findings from the quarterly report.",
    placeholder: "Ask anything…",
  },
}

export const Rounded: Story = {
  args: {
    variant: "rounded",
    value: "Rounded search field",
  },
}

export const Plain: Story = {
  args: {
    variant: "plain",
    value: "Plain inline field",
    placeholder: "Type here…",
  },
}

export const Small: Story = {
  args: {
    size: "small",
    value: "Small field",
  },
}

export const SmallRounded: Story = {
  args: {
    variant: "rounded",
    size: "small",
    value: "Small rounded",
  },
}

export const SmallPlain: Story = {
  args: {
    variant: "plain",
    size: "small",
    value: "Small plain",
  },
}

export const Disabled: Story = {
  args: {
    disabled: true,
    value: "Disabled field",
  },
}

export const Invalid: Story = {
  args: {
    invalid: true,
    value: "Invalid input",
  },
}

export const ReadOnly: Story = {
  args: {
    readOnly: true,
    value: "Read-only content",
  },
}
