import type { Meta, StoryObj } from "@storybook/react-vite"
import type { FC } from "react"
import { TrafficLights } from "./TrafficLights"

const meta = {
  component: TrafficLights,
  id: "file-manager-trafficlights",
  tags: ["autodocs"],
  decorators: [
    (Story: FC) => (
      <div data-file-manager-illustration style={{ padding: "16px" }}>
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof TrafficLights>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
