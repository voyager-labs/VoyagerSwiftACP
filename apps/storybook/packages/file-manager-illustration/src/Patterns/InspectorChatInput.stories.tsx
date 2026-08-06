import type { Meta, StoryObj } from "@storybook/react-vite"
import { InspectorChatInput } from "./InspectorChatInput"

const meta = {
  component: InspectorChatInput,
  tags: ["autodocs"],
  args: {
    requestText: "",
    onRequestTextChange: () => {},
  },
} satisfies Meta<typeof InspectorChatInput>

export default meta
type Story = StoryObj<typeof meta>

export const Empty: Story = {}

export const Draft: Story = {
  args: {
    requestText: "Group these entries by research theme and surface likely duplicates.",
  },
}
