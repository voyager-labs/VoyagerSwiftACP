import type { Meta, StoryObj } from "@storybook/react-vite"
import { Home } from "../../../packages/file-manager-illustration/src/Layouts/Home"
import {
  homeFavorites,
  homeLocations,
  homeRecentChats,
} from "../../../packages/file-manager-illustration/src/data/home-data"

const meta = {
  component: Home,
  tags: ["autodocs"],
  args: {
    favorites: homeFavorites,
    locations: homeLocations,
    recentChats: homeRecentChats,
    standalone: true,
    onFavoriteSelect: () => {},
    onLocationSelect: () => {},
    onNewChat: () => {},
    onChatSelect: () => {},
  },
} satisfies Meta<typeof Home>

export default meta
type Story = StoryObj<typeof meta>

export const Populated: Story = {}

export const Empty: Story = {
  args: {
    favorites: [],
    locations: [],
    recentChats: [],
  },
}

export const Compact: Story = {
  args: {
    compact: true,
  },
}
