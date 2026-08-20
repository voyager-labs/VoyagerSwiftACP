import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerConditionChip } from "../../../../packages/file-manager-illustration/src/Domains/Composer/ComposerConditionChip"

const kindCondition = {
  id: "kind",
  property: "Kind",
  propertySymbol: "tag",
  operator: "Equals",
  value: "pdf",
} as const

const meta = {
  component: ComposerConditionChip,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen">
        <Story />
      </div>
    ),
  ],
  args: { condition: kindCondition },
} satisfies Meta<typeof ComposerConditionChip>

export default meta
type Story = StoryObj<typeof meta>

export const Active: Story = {}
export const Inactive: Story = { args: { inactive: true } }
export const RemoveVisible: Story = { args: { showRemove: true } }
export const DateCondition: Story = {
  args: {
    condition: {
      id: "modified",
      property: "Modified",
      propertySymbol: "calendar.badge.clock",
      operator: "is after",
      value: "This month",
    },
  },
}
