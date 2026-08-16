import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerDateValuePicker } from "./ComposerDateValuePicker"

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
  args: { kind: "date" },
} satisfies Meta<typeof ComposerDateValuePicker>

export default meta
type Story = StoryObj<typeof meta>

export const SingleDate: Story = {}
export const DateRange: Story = { args: { kind: "dateRange" } }
