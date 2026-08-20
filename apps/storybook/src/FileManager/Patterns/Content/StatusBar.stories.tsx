import type { Meta, StoryObj } from "@storybook/react-vite"
import { StatusBar } from "../../../../packages/file-manager-illustration/src/Patterns/Content/StatusBar"

const meta = {
  component: StatusBar,
  tags: ["autodocs"],
  args: {
    selectedLabel: "5 of 72 selected",
    breadcrumb: [
      { label: "Users", symbolName: "folder" },
      { label: "voyager", symbolName: "folder" },
      { label: "Desktop", symbolName: "folder" },
      { label: "Research", symbolName: "folder" },
    ],
  },
} satisfies Meta<typeof StatusBar>

export default meta
type Story = StoryObj<typeof meta>

export const SelectionSummary: Story = {}
