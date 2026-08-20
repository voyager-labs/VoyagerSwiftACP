import type { Meta, StoryObj } from "@storybook/react-vite"
import { PathBreadcrumbItem } from "../../../../packages/file-manager-illustration/src/Pages/FileManager/PathBreadcrumbItem"

const meta = {
  component: PathBreadcrumbItem,
  tags: ["autodocs"],
  args: {
    label: "Research",
    symbolName: "folder",
  },
} satisfies Meta<typeof PathBreadcrumbItem>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const LongLabel: Story = {
  args: {
    label: "2026-Product-Planning-Documents",
    symbolName: "folder",
  },
  decorators: [
    (Story) => (
      <div style={{ width: "160px" }}>
        <Story />
      </div>
    ),
  ],
}
