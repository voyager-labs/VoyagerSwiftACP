import type { Meta, StoryObj } from "@storybook/react-vite"
import { contextMenuActions } from "../data/mock-data"
import { ContextMenu } from "./ContextMenu"

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
