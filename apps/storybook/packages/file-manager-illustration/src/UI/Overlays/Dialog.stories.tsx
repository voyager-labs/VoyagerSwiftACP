import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { Dialog } from "./Dialog"

const meta = {
  component: Dialog,
  tags: ["autodocs"],
  args: {
    title: "Dialog Title",
    children: "This is a dialog with some content describing what the user should do.",
    size: "small",
  },
  render: function Render(args) {
    const [open, setOpen] = useState(false)
    return (
      <>
        <button type="button" className="vc-button" onClick={() => setOpen(true)}>
          Open Dialog
        </button>
        <Dialog {...args} open={open} onClose={() => setOpen(false)} />
      </>
    )
  },
} satisfies Meta<typeof Dialog>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const WithActions: Story = {
  args: {
    children: "Are you sure you want to delete this item? This action cannot be undone.",
    actions: (
      <>
        <button type="button" className="vc-button" onClick={() => {}}>
          Cancel
        </button>
        <button type="button" className="vc-button primary" onClick={() => {}}>
          Delete
        </button>
      </>
    ),
  },
}

export const Medium: Story = {
  args: {
    size: "medium",
    children: (
      <div style={{ display: "grid", gap: "12px" }}>
        <p style={{ margin: 0 }}>This is a medium-sized dialog with more content.</p>
        <p style={{ margin: 0 }}>
          It can accommodate longer messages and additional controls while keeping a
          comfortable reading width.
        </p>
      </div>
    ),
    actions: (
      <>
        <button type="button" className="vc-button" onClick={() => {}}>
          Cancel
        </button>
        <button type="button" className="vc-button primary" onClick={() => {}}>
          Confirm
        </button>
      </>
    ),
  },
}