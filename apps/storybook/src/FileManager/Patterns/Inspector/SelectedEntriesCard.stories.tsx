import type { Meta, StoryObj } from "@storybook/react-vite"
import { SelectedEntriesCard } from "../../../../packages/file-manager-illustration/src/Patterns/Inspector/SelectedEntriesCard"

const meta = {
  component: SelectedEntriesCard,
  tags: ["autodocs"],
  args: {
    count: 5,
    primaryName: "IDC20on20The20Hig...tion.pdf",
  },
} satisfies Meta<typeof SelectedEntriesCard>

export default meta
type Story = StoryObj<typeof meta>

export const Multiple: Story = {}

export const Single: Story = {
  args: {
    count: 1,
    primaryName: "IDC20on20The20Hig...tion.pdf",
  },
}
