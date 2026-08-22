import type { Meta, StoryObj } from "@storybook/react-vite"
import { useState } from "react"
import { Sheet } from "../../../../packages/design-foundation/src/UI/Overlays/Sheet"

const meta = {
  component: Sheet,
  tags: ["autodocs"],
  args: {
    title: "Sheet Title",
    children: "This is a sheet panel with some content.",
    size: "small",
    open: false,
    onClose: () => {},
  },
  render: function Render(args) {
    const [open, setOpen] = useState(false)
    return (
      <>
        <button type="button" className="vc-button" onClick={() => setOpen(true)}>
          Open Sheet
        </button>
        <Sheet {...args} open={open} onClose={() => setOpen(false)} />
      </>
    )
  },
} satisfies Meta<typeof Sheet>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const WithActions: Story = {
  args: {
    children: (
      <div style={{ display: "grid", gap: "12px" }}>
        <p style={{ margin: 0 }}>Configure your preferences below.</p>
      </div>
    ),
    actions: (
      <>
        <button type="button" className="vc-button" onClick={() => {}}>
          Cancel
        </button>
        <button type="button" className="vc-button primary" onClick={() => {}}>
          Save
        </button>
      </>
    ),
  },
}

export const Medium: Story = {
  args: {
    size: "medium",
    title: "Settings",
    children: (
      <div style={{ display: "grid", gap: "16px" }}>
        <p style={{ margin: 0 }}>
          A medium sheet provides more room for settings forms, detailed content, or multi-section
          layouts while keeping the context of the main window visible.
        </p>
        <div className="vc-control-row">
          <div className="vc-control-row-copy">
            <strong>Enable notifications</strong>
            <small>Receive alerts about file changes</small>
          </div>
          <div className="vc-control-row-control">
            <span className="vc-switch" role="switch" aria-checked="false" tabIndex={0}>
              <span className="vc-switch-track" />
            </span>
          </div>
        </div>
        <div className="vc-control-row">
          <div className="vc-control-row-copy">
            <strong>Auto-save</strong>
            <small>Save changes automatically</small>
          </div>
          <div className="vc-control-row-control">
            <span className="vc-switch" role="switch" aria-checked="true" tabIndex={0}>
              <span className="vc-switch-track" />
            </span>
          </div>
        </div>
      </div>
    ),
    actions: (
      <>
        <button type="button" className="vc-button" onClick={() => {}}>
          Cancel
        </button>
        <button type="button" className="vc-button primary" onClick={() => {}}>
          Apply
        </button>
      </>
    ),
  },
}
