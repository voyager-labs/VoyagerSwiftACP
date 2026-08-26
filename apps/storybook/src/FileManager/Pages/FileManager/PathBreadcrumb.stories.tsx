import type { Meta, StoryObj } from "@storybook/react-vite"
import { PathBreadcrumb } from "../../../../packages/file-manager-illustration/src/Pages/FileManager/PathBreadcrumb"

const meta = {
  component: PathBreadcrumb,
  tags: ["autodocs"],
  args: {
    segments: [
      { label: "Macintosh HD", symbolName: "internaldrive" },
      { label: "Users", symbolName: "folder" },
      { label: "voyager", symbolName: "folder" },
      { label: "Desktop", symbolName: "folder" },
      { label: "Research", symbolName: "folder" },
    ],
  },
} satisfies Meta<typeof PathBreadcrumb>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const LongLabels: Story = {
  args: {
    segments: [
      { label: "Macintosh HD", symbolName: "internaldrive" },
      { label: "Users", symbolName: "folder" },
      { label: "voyager", symbolName: "folder" },
      {
        label: "2026-Product-Planning-Documents",
        symbolName: "folder",
      },
      {
        label: "Quarterly-Business-Review-Notes",
        symbolName: "folder",
      },
      {
        label: "Final-Revenue-Projection-Models",
        symbolName: "folder",
      },
    ],
  },
  decorators: [
    (Story) => (
      <div style={{ width: "320px" }}>
        <Story />
      </div>
    ),
  ],
}
