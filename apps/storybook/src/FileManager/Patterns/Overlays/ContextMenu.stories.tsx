import type { Meta, StoryObj } from "@storybook/react-vite"
import { ContextMenu } from "../../../../packages/file-manager-illustration/src/Patterns/Overlays/ContextMenu"
import { contextMenuActions } from "../../../../packages/file-manager-illustration/src/data/mock-data"

const meta = {
  component: ContextMenu,
  tags: ["autodocs"],
  args: {
    actions: contextMenuActions,
  },
} satisfies Meta<typeof ContextMenu>

export default meta
type Story = StoryObj<typeof meta>

export const SelectionMenu: Story = {}
