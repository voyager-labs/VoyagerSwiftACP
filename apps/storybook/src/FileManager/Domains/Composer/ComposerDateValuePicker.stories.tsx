import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerDateValuePicker } from "../../../../packages/file-manager-illustration/src/Domains/Composer/ComposerDateValuePicker"

const meta = {
  component: ComposerDateValuePicker,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen picker">
        <Story />
      </div>
    ),
  ],
  args: { kind: "date", initialValue: "2026-08-21" },
} satisfies Meta<typeof ComposerDateValuePicker>

export default meta
type Story = StoryObj<typeof meta>

export const SingleDate: Story = {
  args: { initialDateMode: "absolute" },
}
export const DateRange: Story = {
  args: { kind: "dateRange", initialValue: "2024-01-01 - 2024-12-31", editingIndex: 1 },
}
