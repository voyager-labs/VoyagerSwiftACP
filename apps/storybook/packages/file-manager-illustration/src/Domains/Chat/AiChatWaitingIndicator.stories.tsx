import type { Meta, StoryObj } from "@storybook/react-vite"
import { AiChatWaitingIndicator } from "./AiChatWaitingIndicator"

const meta = {
  component: AiChatWaitingIndicator,
  tags: ["autodocs"],
} satisfies Meta<typeof AiChatWaitingIndicator>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  render: () => (
    <div style={{ padding: "24px" }}>
      <AiChatWaitingIndicator />
    </div>
  ),
}
