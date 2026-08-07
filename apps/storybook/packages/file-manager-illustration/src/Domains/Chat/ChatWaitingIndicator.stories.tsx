import type { Meta, StoryObj } from "@storybook/react-vite"
import { ChatWaitingIndicator } from "./ChatWaitingIndicator"

const meta = {
  component: ChatWaitingIndicator,
  tags: ["autodocs"],
} satisfies Meta<typeof ChatWaitingIndicator>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  render: () => (
    <div style={{ padding: "24px" }}>
      <ChatWaitingIndicator />
    </div>
  ),
}
