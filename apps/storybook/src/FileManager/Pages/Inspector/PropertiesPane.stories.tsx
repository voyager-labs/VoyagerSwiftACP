import type { Meta, StoryObj } from "@storybook/react-vite"
import { PropertiesPane } from "../../../../packages/file-manager-illustration/src/Pages/Inspector/PropertiesPane"
import { files } from "../../../../packages/file-manager-illustration/src/data/mock-data"

const primaryEntry = files[0]

const meta = {
  component: PropertiesPane,
  tags: ["autodocs"],
  args: {
    selectedEntries: files.slice(0, 5),
    primaryEntry,
  },
} satisfies Meta<typeof PropertiesPane>

export default meta
type Story = StoryObj<typeof meta>

export const SelectionProperties: Story = {}

export const SingleSelection: Story = {
  args: {
    selectedEntries: [primaryEntry],
    primaryEntry,
  },
}
