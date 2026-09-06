import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { Popover } from "../../../../packages/design-foundation/src/UI/Overlays/Popover"

const meta = {
  component: Popover,
  tags: ["autodocs"],
  args: {
    trigger: "Open",
    children: "Popover content",
    placement: "bottom",
    open: false,
    onOpenChange: () => {},
  },
  render: function Render(args) {
    const [open, setOpen] = useState(false)
    return (
      <div style={{ display: "flex", justifyContent: "center", padding: "80px 0" }}>
        <Popover {...args} open={open} onOpenChange={setOpen} />
      </div>
    )
  },
} satisfies Meta<typeof Popover>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const WithRichContent: Story = {
  args: {
    trigger: "Actions",
    children: (
      <div style={{ display: "grid", gap: "4px", minWidth: "160px" }}>
        <button type="button" className="fm-menu-item">
          Rename
        </button>
        <button type="button" className="fm-menu-item">
          Duplicate
        </button>
        <button type="button" className="fm-menu-item">
          Move to…
        </button>
        <div className="vc-divider" />
        <button type="button" className="fm-menu-item">
          Delete
        </button>
      </div>
    ),
  },
}

export const Top: Story = {
  args: { placement: "top", trigger: "Top" },
}

export const Right: Story = {
  args: { placement: "right", trigger: "Right" },
}

export const Left: Story = {
  args: { placement: "left", trigger: "Left" },
}
