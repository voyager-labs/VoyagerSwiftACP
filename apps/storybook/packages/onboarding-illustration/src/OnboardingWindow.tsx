import { useEffect, useState } from "react"
import type { FC, ReactNode } from "react"
import { OnboardingLayout } from "./OnboardingLayout"
import { AiProviderStep, CompleteStep, PermissionsStep } from "./OnboardingSteps"
import type { OnboardingState, OnboardingStep, OnboardingWindowProps } from "./model"
import "./onboarding-styles"

const STEPS: readonly OnboardingStep[] = ["welcome", "permissions", "aiProvider", "complete"]

const STEP_COPY: Readonly<
  Record<OnboardingStep, { readonly title: string; readonly subtitle: string }>
> = {
  welcome: { title: "Welcome", subtitle: "A quick setup before you dive in." },
  permissions: { title: "Permissions", subtitle: "Just a couple of permissions to get you going." },
  aiProvider: { title: "AI Provider", subtitle: "Connect a provider now or set it up later." },
  complete: { title: "Start your voyage", subtitle: "All set. You're ready to start." },
}

function isComplete(state: OnboardingState, step: OnboardingStep): boolean {
  if (step === "welcome") {
    return true
  }
  if (step === "permissions") {
    return (
      state.permissions.fullDiskAccess === "Granted" &&
      state.permissions.folders.every(({ status }) => status === "Granted")
    )
  }
  if (step === "aiProvider") {
    return state.aiPhase === "ready"
  }
  return false
}

function nextDisabledMessage(state: OnboardingState, step: OnboardingStep): string | null {
  if (step === "permissions") {
    if (state.permissions.fullDiskAccess !== "Granted") {
      return "Turn on Full Disk Access to continue."
    }
    if (state.permissions.folders.some(({ status }) => status !== "Granted")) {
      return "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue."
    }
  }
  if (step === "aiProvider" && !isComplete(state, step)) {
    return "Connect a provider or choose Set up later to continue."
  }
  return null
}

function stepContent(state: OnboardingState, step: OnboardingStep): ReactNode {
  switch (step) {
    case "welcome":
      return null
    case "permissions":
      return <PermissionsStep state={state.permissions} />
    case "aiProvider":
      return <AiProviderStep state={state} />
    case "complete":
      return <CompleteStep phase={state.completePhase} />
    default:
      return step satisfies never
  }
}

export const OnboardingWindow: FC<OnboardingWindowProps> = ({ state }) => {
  const [step, setStep] = useState<OnboardingStep>(state.step)

  useEffect(() => {
    setStep(state.step)
  }, [state.step])

  const currentIndex = STEPS.indexOf(step)
  const canGoBack = currentIndex > 0
  const canGoNext = isComplete(state, step)
  const copy = STEP_COPY[step]
  const disabledMessage = nextDisabledMessage(state, step)

  return (
    <OnboardingLayout
      steps={STEPS}
      currentStep={step}
      canGoBack={canGoBack}
      nextDisabled={step === "complete" ? state.completePhase === "opening" : !canGoNext}
      onBack={() => setStep(STEPS[currentIndex - 1] ?? step)}
      onNext={() => {
        if (step !== "complete") {
          setStep(STEPS[currentIndex + 1] ?? step)
        }
      }}
      title={copy.title}
      subtitle={copy.subtitle}
      disabledMessage={disabledMessage}
    >
      {stepContent(state, step)}
    </OnboardingLayout>
  )
}

OnboardingWindow.displayName = "OnboardingWindow"
