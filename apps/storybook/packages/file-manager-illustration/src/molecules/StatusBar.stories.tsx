import type { Meta, StoryObj } from "@storybook/react-vite"
import { StatusBar } from "./StatusBar"

const meta = {
  component: StatusBar,
  tags: ["autodocs"],
  args: {
    selectedLabel: "5 of 72 selected",
    breadcrumb: "Users / voyager / Desktop / Research",
  },
} satisfies Meta<typeof StatusBar>

export default meta
type Story = StoryObj<typeof meta>

export const SelectionSummary: Story = {}
