import type { Meta, StoryObj } from "@storybook/react-vite"
import { homeFavorites, homeLocations, homeRecentChats } from "../data/home-data"
import { Home } from "./Home"

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
  },
}

export const Compact: Story = {
  args: {
    compact: true,
  },
}
