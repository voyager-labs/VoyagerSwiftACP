import type { Meta, StoryObj } from "@storybook/react-vite"
import { OnboardingWindow } from "../../../packages/onboarding-illustration/src/OnboardingWindow"
import {
  aiErrorState,
  aiLoadingState,
  aiProvidersState,
  completeErrorState,
  completeOpeningState,
  completeState,
  permissionsBlockedState,
  permissionsGrantedState,
  permissionsRequestingState,
  welcomeState,
} from "../../../packages/onboarding-illustration/src/data/onboarding-fixtures"

const meta = {
  component: OnboardingWindow,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  args: { state: welcomeState },
} satisfies Meta<typeof OnboardingWindow>

export default meta
type Story = StoryObj<typeof meta>

export const Welcome: Story = {}

export const PermissionsNeedsAction: Story = {
  args: { state: permissionsBlockedState },
}

export const PermissionsRequestingAccess: Story = {
  args: { state: permissionsRequestingState },
}

export const PermissionsGranted: Story = {
  args: { state: permissionsGrantedState },
}

export const AiProviders: Story = {
  args: { state: aiProvidersState },
}

export const AiProvidersLoading: Story = {
  args: { state: aiLoadingState },
}

export const AiProvidersError: Story = {
  args: { state: aiErrorState },
}

export const Complete: Story = {
  args: { state: completeState },
}

export const CompleteOpening: Story = {
  args: { state: completeOpeningState },
}

export const CompleteError: Story = {
  args: { state: completeErrorState },
}
