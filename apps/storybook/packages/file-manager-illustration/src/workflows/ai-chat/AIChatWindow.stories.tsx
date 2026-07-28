import type { Meta, StoryObj } from "@storybook/react-vite"
import { AIChatWindow } from "./AIChatWindow"
import { failedChat, processingChat, readyChat, sessionsChat, unconnectedChat } from "./mock-data"

const meta = {
  component: AIChatWindow,
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    state: readyChat,
  },
} satisfies Meta<typeof AIChatWindow>

export default meta
type Story = StoryObj<typeof meta>

export const Ready: Story = {}

export const SessionsList: Story = {
  args: {
    state: sessionsChat,
  },
}

export const ProcessingLockedModel: Story = {
  args: {
    state: processingChat,
  },
}

export const Unconnected: Story = {
  args: {
    state: unconnectedChat,
  },
}

export const FailedModelUnavailable: Story = {
  args: {
    state: failedChat,
  },
}
