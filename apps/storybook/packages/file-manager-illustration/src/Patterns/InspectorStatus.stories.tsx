import type { Meta, StoryObj } from "@storybook/react-vite"
import { InspectorStatus } from "./InspectorStatus"

const meta = {
  component: InspectorStatus,
  tags: ["autodocs"],
} satisfies Meta<typeof InspectorStatus>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
