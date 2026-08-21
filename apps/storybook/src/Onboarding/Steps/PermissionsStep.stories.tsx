import type { Meta, StoryObj } from "@storybook/react-vite"
import { PermissionsStep } from "../../../packages/onboarding-illustration/src/OnboardingSteps"
import {
  permissionsBlockedState,
  permissionsGrantedState,
  permissionsRequestingState,
} from "../../../packages/onboarding-illustration/src/data/onboarding-fixtures"
import "../../../packages/onboarding-illustration/src/onboarding-styles"

const meta = {
  component: PermissionsStep,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  decorators: [
    (Story) => (
      <div data-design-foundation data-onboarding-illustration>
        <main
          className="onb-specimen"
          style={{ minHeight: "100dvh", padding: 48, background: "var(--macos-under-page-background-color)" }}
        >
          <header className="onb-summary" style={{ maxWidth: 720 }}>
            <span>Onboarding component</span>
            <h1>Permissions</h1>
          </header>
          <div style={{ maxWidth: 720 }}>
            <Story />
          </div>
        </main>
      </div>
    ),
  ],
  args: { state: permissionsBlockedState.permissions },
} satisfies Meta<typeof PermissionsStep>

export default meta
type Story = StoryObj<typeof meta>

export const Blocked: Story = {}

export const RequestingAccess: Story = {
  args: { state: permissionsRequestingState.permissions },
}

export const Granted: Story = {
  args: { state: permissionsGrantedState.permissions },
}
