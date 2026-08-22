import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerValuePicker } from "../../../../packages/file-manager-illustration/src/Domains/Composer/ComposerValuePicker"

const meta = {
  component: ComposerValuePicker,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen picker">
        <Story />
      </div>
    ),
  ],
  args: { picker: { kind: "value", editor: { kind: "text" } } },
} satisfies Meta<typeof ComposerValuePicker>

export default meta
type Story = StoryObj<typeof meta>

export const Text: Story = {}
export const NumericValue: Story = {
  args: { picker: { kind: "value", editor: { kind: "number" } } },
}
export const SizeWithUnit: Story = {
  args: {
    picker: { kind: "value", editor: { kind: "number", units: ["Byte", "KB", "MB", "GB"] } },
  },
}
export const NumberRange: Story = {
  args: { picker: { kind: "value", editor: { kind: "numberRange" } } },
}
export const AbsoluteDate: Story = { args: { picker: { kind: "value", editor: { kind: "date" } } } }
export const DateRange: Story = {
  args: { picker: { kind: "value", editor: { kind: "dateRange" } } },
}
export const BooleanValue: Story = {
  args: { picker: { kind: "value", editor: { kind: "boolean" } } },
}
export const StringList: Story = { args: { picker: { kind: "value", editor: { kind: "list" } } } }
export const CategoricalList: Story = {
  args: {
    picker: {
      kind: "value",
      editor: { kind: "list", suggestions: ["PDF", "Document", "Image", "Folder"] },
    },
  },
}
export const NoValue: Story = { args: { picker: { kind: "value", editor: { kind: "none" } } } }
export const ValidationError: Story = {
  args: { picker: { kind: "value", editor: { kind: "number" }, error: "Enter a valid number." } },
}
