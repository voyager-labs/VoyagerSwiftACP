import type { Meta, StoryObj } from "@storybook/react-vite"
import { InspectorToolbar } from "./InspectorToolbar"

const meta = {
  component: InspectorToolbar,
  tags: ["autodocs"],
  args: {
    mode: "chat",
    onModeChange: () => {},
  },
} satisfies Meta<typeof InspectorToolbar>

export default meta
type Story = StoryObj<typeof meta>

export const ChatMode: Story = {}

export const PropertiesMode: Story = {
  args: {
    mode: "properties",
  },
}
