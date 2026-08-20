import type { Meta, StoryObj } from "@storybook/react-vite"
import { SidebarIcon } from "../../../../packages/design-foundation/src/UI/Navigation/SidebarIcon"

const meta = {
  component: SidebarIcon,
  tags: ["autodocs"],
  argTypes: {
    icon: {
      control: "select",
      options: ["folder", "home", "folder-blue", "collection", "chat"],
    },
  },
  args: {
    icon: "folder",
  },
} satisfies Meta<typeof SidebarIcon>

export default meta
type Story = StoryObj<typeof meta>

export const Folder: Story = {}

export const Home: Story = {
  args: {
    icon: "home",
  },
}

export const FolderBlue: Story = {
  args: {
    icon: "folder-blue",
  },
}

export const Collection: Story = {
  args: {
    icon: "collection",
  },
}

export const Chat: Story = {
  args: {
    icon: "chat",
  },
}
