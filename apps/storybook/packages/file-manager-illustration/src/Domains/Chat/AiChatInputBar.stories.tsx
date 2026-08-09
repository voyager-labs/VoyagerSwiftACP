import type { Meta, StoryObj } from "@storybook/react-vite"
import { AiChatInputBar } from "./AiChatInputBar"

const meta = {
  component: AiChatInputBar,
  tags: ["autodocs"],
  args: {
    requestText: "",
    onRequestTextChange: () => {},
  },
} satisfies Meta<typeof AiChatInputBar>

export default meta
type Story = StoryObj<typeof meta>

export const Empty: Story = {}

export const Draft: Story = {
  args: {
    requestText: "Group these entries by research theme and surface likely duplicates.",
  },
}
