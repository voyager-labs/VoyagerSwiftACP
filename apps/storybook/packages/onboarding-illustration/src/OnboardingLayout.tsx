import { Button, TrafficLights } from "@voyager-labs/design-foundation"
import type { FC, ReactNode } from "react"
import type { OnboardingStep } from "./model"

interface OnboardingStageProps {
  readonly children: ReactNode
}

const OnboardingStage: FC<OnboardingStageProps> = ({ children }) => (
  <main className="onb-stage">{children}</main>
)

interface OnboardingWindowFrameProps {
  readonly children: ReactNode
}

const OnboardingWindowFrame: FC<OnboardingWindowFrameProps> = ({ children }) => (
  <section className="onb-window" aria-label="Voyager Onboarding">
    <div className="onb-window-controls">
      <TrafficLights />
    </div>
    <div className="onb-shell">{children}</div>
  </section>
)

interface OnboardingTopBarProps {
  readonly steps: readonly OnboardingStep[]
  readonly currentStep: OnboardingStep
  readonly canGoBack: boolean
  readonly nextDisabled: boolean
  readonly onBack: () => void
  readonly onNext: () => void
}

const OnboardingTopBar: FC<OnboardingTopBarProps> = ({
  steps,
  currentStep,
  canGoBack,
  nextDisabled,
  onBack,
  onNext,
}) => (
  <nav className="onb-topbar" aria-label="Onboarding navigation">
    <div className="onb-side-slot is-leading">
      <Button variant="subtle" disabled={!canGoBack} onClick={onBack}>
        Back
      </Button>
    </div>

    <ol className="onb-progress" aria-label="Onboarding progress">
      {steps.map((candidate) => (
        <li
          key={candidate}
          className={candidate === currentStep ? "is-active" : ""}
          aria-current={candidate === currentStep ? "step" : undefined}
        />
      ))}
    </ol>

    <div className="onb-side-slot is-trailing">
      <Button variant="primary" disabled={nextDisabled} onClick={onNext}>
        {currentStep === "complete" ? "Complete (Enter)" : "Next (Enter)"}
      </Button>
    </div>
  </nav>
)

interface OnboardingSummaryProps {
  readonly title: string
  readonly subtitle: string
}

const OnboardingSummary: FC<OnboardingSummaryProps> = ({ title, subtitle }) => (
  <header className="onb-summary">
    <span>Voyager</span>
    <h1>{title}</h1>
    <p>{subtitle}</p>
  </header>
)

interface OnboardingContentLayoutProps extends OnboardingSummaryProps {
  readonly children: ReactNode
}

const OnboardingContentLayout: FC<OnboardingContentLayoutProps> = ({
  title,
  subtitle,
  children,
}) => (
  <div className="onb-content">
    <OnboardingSummary title={title} subtitle={subtitle} />
    <div className="onb-step-content">{children}</div>
  </div>
)

interface OnboardingLayoutProps extends OnboardingTopBarProps, OnboardingSummaryProps {
  readonly disabledMessage: string | null
  readonly children: ReactNode
}

export const OnboardingLayout: FC<OnboardingLayoutProps> = ({
  steps,
  currentStep,
  canGoBack,
  nextDisabled,
  onBack,
  onNext,
  title,
  subtitle,
  disabledMessage,
  children,
}) => (
  <div data-design-foundation data-onboarding-illustration>
    <OnboardingStage>
      <OnboardingWindowFrame>
        <OnboardingTopBar
          steps={steps}
          currentStep={currentStep}
          canGoBack={canGoBack}
          nextDisabled={nextDisabled}
          onBack={onBack}
          onNext={onNext}
        />
        {disabledMessage ? <p className="onb-disabled-message">{disabledMessage}</p> : null}
        <OnboardingContentLayout title={title} subtitle={subtitle}>
          {children}
        </OnboardingContentLayout>
      </OnboardingWindowFrame>
    </OnboardingStage>
  </div>
)
