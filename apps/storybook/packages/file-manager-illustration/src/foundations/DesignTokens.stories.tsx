import type { Meta, StoryObj } from "@storybook/react-vite"
import "../styles/design-token-overview.css"
import { DesignTokenOverview } from "./DesignTokenOverview"

const meta = {
  component: DesignTokenOverview,
  id: "file-manager-design-tokens",
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    baseline: "Tahoe",
    colorScheme: "System",
  },
} satisfies Meta<typeof DesignTokenOverview>

export default meta
type Story = StoryObj<typeof meta>

export const Overview: Story = {
  render: (_args, context) => {
    const baseline = context.globals.visualBaseline === "sequoia" ? "Sequoia" : "Tahoe"
    const colorScheme =
      context.globals.colorScheme === "dark"
        ? "Dark"
        : context.globals.colorScheme === "light"
          ? "Light"
          : "System"

    return <DesignTokenOverview baseline={baseline} colorScheme={colorScheme} />
  },
}
