import type { Meta, StoryObj } from "@storybook/react-vite"
import { PullDownButton } from "../../../../packages/design-foundation/src/UI/Controls/PullDownButton"

const fn = (): (() => void) => () => {}

const actions = [
  { value: "duplicate", label: "Duplicate" },
  { value: "move", label: "Move to…" },
  { value: "compress", label: "Compress" },
  { value: "delete", label: "Delete", disabled: true },
] as const

const meta = {
  component: PullDownButton,
  tags: ["autodocs"],
  args: {
    label: "Actions",
    options: actions,
    onSelect: fn(),
  },
} satisfies Meta<typeof PullDownButton>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const WithDetail: Story = {
  args: {
    label: "Sort by",
    options: [
      { value: "name", label: "Name", detail: "A → Z" },
      { value: "date", label: "Date", detail: "Newest first" },
      { value: "size", label: "Size", detail: "Largest first" },
      { value: "kind", label: "Kind", detail: "Group by type" },
    ],
  },
}

export const DisabledOption: Story = {
  args: {
    options: [
      { value: "share", label: "Share…" },
      { value: "rename", label: "Rename" },
      { value: "lock", label: "Lock", disabled: true },
      { value: "info", label: "Get Info" },
    ],
  },
}

export const Disabled: Story = {
  args: { disabled: true },
}

export const ManyOptions: Story = {
  args: {
    label: "Menu",
    options: Array.from({ length: 15 }, (_, i) => ({
      value: `item-${i}`,
      label: `Menu item ${i + 1}`,
    })),
  },
}

export const CustomLabel: Story = {
  args: {
    label: "↗ Share",
    options: [
      { value: "airdrop", label: "AirDrop" },
      { value: "mail", label: "Mail" },
      { value: "messages", label: "Messages" },
      { value: "notes", label: "Notes" },
    ],
  },
}
