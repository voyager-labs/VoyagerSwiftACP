import type { Meta, StoryObj } from "@storybook/react-vite"
import { ComposerShell } from "./ComposerShell"
import { draftComposer, failedComposer, idleComposer, searchingComposer } from "./mock-data"

const meta = {
  component: ComposerShell,
  tags: ["autodocs"],
  parameters: {
    layout: "fullscreen",
  },
  args: {
    draft: draftComposer,
  },
} satisfies Meta<typeof ComposerShell>

export default meta
type Story = StoryObj<typeof meta>

export const Draft: Story = {}

export const Idle: Story = {
  args: {
    draft: idleComposer,
  },
}

export const SearchingWithScopeFeedback: Story = {
  args: {
    draft: searchingComposer,
  },
}

export const FailedConversion: Story = {
  args: {
    draft: failedComposer,
  },
}
