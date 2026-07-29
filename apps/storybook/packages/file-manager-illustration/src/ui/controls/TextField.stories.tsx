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
