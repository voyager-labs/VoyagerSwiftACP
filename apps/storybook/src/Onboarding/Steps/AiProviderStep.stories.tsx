import type { Meta, StoryObj } from "@storybook/react-vite"
import { AiProviderStep } from "../../../packages/onboarding-illustration/src/OnboardingSteps"
import {
  aiErrorState,
  aiLoadingState,
  aiProvidersState,
} from "../../../packages/onboarding-illustration/src/data/onboarding-fixtures"
import "../../../packages/onboarding-illustration/src/onboarding-styles"

const meta = {
  component: AiProviderStep,
  tags: ["autodocs"],
  parameters: { layout: "fullscreen" },
  decorators: [
    (Story) => (
      <div data-design-foundation data-onboarding-illustration>
        <main className="onb-stage">
          <section className="onb-window" aria-label="AI provider step preview">
            <div className="onb-shell">
              <header className="onb-summary">
                <span>Onboarding component</span>
                <h1>AI Provider</h1>
              </header>
              <Story />
            </div>
          </section>
        </main>
      </div>
    ),
  ],
  args: { state: aiProvidersState },
} satisfies Meta<typeof AiProviderStep>

export default meta
type Story = StoryObj<typeof meta>

export const Providers: Story = {}

export const Loading: Story = {
  args: { state: aiLoadingState },
}

export const LoadError: Story = {
  args: { state: aiErrorState },
}
