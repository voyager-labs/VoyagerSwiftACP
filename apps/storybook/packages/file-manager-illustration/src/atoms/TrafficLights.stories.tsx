import type { Meta, StoryObj } from "@storybook/react-vite"
import { TrafficLights } from "./TrafficLights"

const meta = {
  component: TrafficLights,
  id: "file-manager-trafficlights",
  tags: ["autodocs"],
} satisfies Meta<typeof TrafficLights>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}
