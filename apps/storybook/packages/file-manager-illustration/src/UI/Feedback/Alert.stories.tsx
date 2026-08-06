import type { Meta, StoryObj } from "@storybook/react-vite"
import { Button } from "../Controls/Button"
import { Alert } from "./Alert"

const meta = {
  component: Alert,
  tags: ["autodocs"],
  args: {
    title: "Something happened",
  },
} satisfies Meta<typeof Alert>

export default meta
type Story = StoryObj<typeof meta>

export const Informational: Story = {
  args: {
    variant: "informational",
    title: "Information",
    message: "This is an informational alert with useful context.",
  },
}

export const Warning: Story = {
  args: {
    variant: "warning",
    title: "Warning",
    message: "This action cannot be undone. Are you sure you want to proceed?",
  },
}

export const Critical: Story = {
  args: {
    variant: "critical",
    title: "Critical Error",
    message: "An unexpected error occurred while processing your request.",
  },
}

export const TitleOnly: Story = {
  args: {
    title: "Short alert with no body",
  },
}

export const WithActions: Story = {
  args: {
    variant: "warning",
    title: "Unsaved changes",
    message: "You have unsaved changes that will be lost if you close this window.",
    actions: (
      <>
        <Button variant="subtle">Cancel</Button>
        <Button variant="destructive">Discard</Button>
      </>
    ),
  },
}

export const CriticalWithAction: Story = {
  args: {
    variant: "critical",
    title: "Connection lost",
    message:
      "Your connection to the server has been interrupted. Check your network and try again.",
    actions: <Button variant="primary">Retry</Button>,
  },
}
