import type { Meta, StoryObj } from "@storybook/react-vite"
import { SearchField } from "../../../../packages/file-manager-illustration/src/Patterns/Content/SearchField"

const meta = {
  component: SearchField,
  tags: ["autodocs"],
  args: {
    value: "voyager pdf",
    placeholder: "Search Voyager",
    resultCount: 12,
  },
} satisfies Meta<typeof SearchField>

export default meta
type Story = StoryObj<typeof meta>

export const Filtered: Story = {}

export const Empty: Story = {
  args: { value: "", resultCount: 0 },
}
