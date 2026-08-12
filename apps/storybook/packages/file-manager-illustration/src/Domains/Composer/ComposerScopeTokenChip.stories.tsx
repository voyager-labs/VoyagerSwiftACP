import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerScopeTokenChip } from "./ComposerScopeTokenChip"

const meta = {
  component: ComposerScopeTokenChip,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen">
        <Story />
      </div>
    ),
  ],
  args: { title: "This Mac" },
} satisfies Meta<typeof ComposerScopeTokenChip>

export default meta
type Story = StoryObj<typeof meta>

export const RootScope: Story = {}
export const ExplicitScope: Story = {
  args: { title: "Documents", path: "/VoyagerFixtures/Documents", removable: true },
}
export const RemoveVisible: Story = {
  args: {
    title: "Documents",
    path: "/VoyagerFixtures/Documents",
    removable: true,
    showRemove: true,
  },
}
