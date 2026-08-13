import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerOperatorPicker } from "./ComposerOperatorPicker"
import { composerPropertyOptions } from "./composer-condition-options"

const meta = {
  component: ComposerOperatorPicker,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen picker">
        <Story />
      </div>
    ),
  ],
  args: {
    picker: {
      kind: "operator",
      conditionID: "modification_date",
      selectedCode: "eq",
      options: composerPropertyOptions[3].operators,
    },
  },
} satisfies Meta<typeof ComposerOperatorPicker>

export default meta
type Story = StoryObj<typeof meta>

export const DateOperators: Story = {}
