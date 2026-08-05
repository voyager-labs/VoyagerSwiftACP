import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComboBox } from "./ComboBox"
import type { ControlOption } from "./ControlOption"

const sampleOptions = [
  { value: "recents", label: "Recents" },
  { value: "documents", label: "Documents" },
  { value: "desktop", label: "Desktop" },
  { value: "downloads", label: "Downloads" },
  { value: "applications", label: "Applications", detail: "⌘A" },
] satisfies ControlOption[]

const meta = {
  component: ComboBox,
  tags: ["autodocs"],
  args: {
    options: sampleOptions,
    placeholder: "Choose a location…",
  },
} satisfies Meta<typeof ComboBox>

export default meta
type Story = StoryObj<typeof meta>

export const Unselected: Story = {}

export const Selected: Story = {
  args: {
    value: "documents",
  },
}

export const Open: Story = {
  args: {
    open: true,
  },
}

export const OpenWithSelection: Story = {
  args: {
    open: true,
    value: "desktop",
  },
}

export const Disabled: Story = {
  args: {
    disabled: true,
    value: "documents",
  },
}

export const CustomStyle: Story = {
  args: {
    value: "downloads",
    style: { width: 240 },
  },
}
