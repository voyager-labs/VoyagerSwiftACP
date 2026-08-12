import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerScopeSummaryChip } from "./ComposerScopeSummaryChip"

const meta = {
  component: ComposerScopeSummaryChip,
  tags: ["autodocs"],
  decorators: [
    (Story) => (
      <div className="collection-composer-specimen wide">
        <Story />
      </div>
    ),
  ],
  args: { primary: "This Mac", compact: true },
} satisfies Meta<typeof ComposerScopeSummaryChip>

export default meta
type Story = StoryObj<typeof meta>

export const RootOnly: Story = {}
export const SelectedFolder: Story = {
  args: { primary: "Documents", secondary: "Includes subfolders" },
}
export const MultipleWithException: Story = {
  args: { primary: "2 folders", secondary: "Includes subfolders", badge: "1 excluded" },
}
