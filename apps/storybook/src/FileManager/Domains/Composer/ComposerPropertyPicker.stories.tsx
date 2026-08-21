import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerPropertyPicker } from "../../../../packages/file-manager-illustration/src/Domains/Composer/ComposerPropertyPicker"
import { composerPropertyOptions } from "../../../../packages/file-manager-illustration/src/Domains/Composer/composer-condition-options"

const meta = {
  component: ComposerPropertyPicker,
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
      kind: "property",
      items: composerPropertyOptions,
    },
  },
} satisfies Meta<typeof ComposerPropertyPicker>

export default meta
type Story = StoryObj<typeof meta>

export const Root: Story = {}
